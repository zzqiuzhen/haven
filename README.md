# EchoShelf

> **自建有声书系统** —— 把 115 网盘里的有声书，通过 **MoviePilot 302/strm** 方案接入自建 **Audiobookshelf**，用自研 iOS 客户端 **EchoShelf** 播放（秒播 / 缓存 / 锁屏控制）。
>
> iOS 16+ · Flutter · 未签名 IPA（自签安装）

---

## 目录

- [一、项目总览](#一项目总览)
- [二、整体架构与数据流](#二整体架构与数据流)
- [三、部署一：MoviePilot + 115strm 插件（生成 strm）](#三部署一moviepilot--115strm-插件生成-strm)
- [四、部署二：Audiobookshelf 302strm（入库有声书）](#四部署二audiobookshelf-302strm入库有声书)
- [五、部署三：CloudDrive2（缓存有声书）](#五部署三clouddrive2缓存有声书)
- [六、客户端 EchoShelf（iOS）](#六客户端-echoshelfios)
- [七、路径 / 端口速查](#七路径--端口速查)
- [八、常见问题排查](#八常见问题排查)
- [九、维护与升级](#九维护与升级)
- [许可](#许可)

> 📌 文中 `<NAS-IP>`、`<Tailscale-IP>` 为占位符，请替换为你自己的服务器地址；`/data`、`/media` 代表存储/媒体根目录（按实际结构调整）。

---

## 一、项目总览

EchoShelf 是一套「**115 网盘有声书 → 自建 Audiobookshelf → iOS 客户端**」的完整私有听书方案，核心是三步：

1. **部署 MoviePilot 的 115strm 插件** —— 把 115 网盘里的有声书目录映射成一批 `.strm` 占位文件，文件内容只存一个 302 重定向地址；
2. **部署 Audiobookshelf 302strm 项目** —— 魔改版 Audiobookshelf 把 `.strm` 目录当成有声书库入库，播放时后台把 302 解析到 115 CDN 并流式代理；
3. **部署 CloudDrive2** —— 把 115 网盘挂载成 NAS 本地路径，实现「**本地化缓存**」：把正在听的书提前复制到本地盘，秒开、稳定、断网可听，同时作为 WMA 转码的数据源。

前端由自研 iOS 客户端 **EchoShelf** 负责书库浏览、播放、缓存、锁屏控制。

---

## 二、整体架构与数据流

```
                        115 网盘（有声书原始文件）
                            │
        ┌───────────────────┼────────────────────────┐
        │ CookieCloud/扫码   │                        │
        ▼                   ▼                        ▼
  CloudDrive2           MoviePilot               CloudDrive2
  (挂载到 NAS)        (+115strm 插件)            (源文件读取)
        │                   │                        │
        │ 挂载              │ 生成 .strm              │ 本地化复制
        ▼                   ▼                        ▼
 /media/115-有声书        .strm 占位文件          /media/115-有声书-local
        │  (只读)            │  (只读)               │  (只读)
        └─────────┬─────────┘                        │
                  ▼                                  │
        Audiobookshelf 302strm 魔改版（302 代理 / WMA→AAC 转码 / 本地化）
                  ▲
                  │ HTTP (ABS API)
                  │
          EchoShelf iOS 客户端
   （本地缓存 → 本地镜像 → 直连 302 → 服务端代理 → AAC 转码）
```

**播放优先级（客户端）**：手机本地缓存 → NAS 本地镜像（CloudDrive2 本地化） → 极速直连（302 到 115 CDN） → 服务端代理 → WMA 走 AAC 转码。
命中前两级时**零网络、秒开**。

---

## 三、部署一：MoviePilot + 115strm 插件（生成 strm）

**目标**：把 115 网盘里的有声书目录，映射成 NAS 上一批 `.strm` 文件（每个文件存一个 302 地址），供 Audiobookshelf 入库。

### 3.1 前置条件

- NAS 已装 Docker；
- 115 网盘账号可用；
- 建议同时装 **CookieCloud**（浏览器插件 + 服务端）自动同步 115 登录 Cookie，避免过期后频繁重登。

### 3.2 部署 MoviePilot（Docker Compose）

```yaml
services:
  moviepilot:
    image: jxxghp/moviepilot-v2:latest
    container_name: moviepilot
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
    volumes:
      - /data/docker/moviepilot/config:/config
      - /media:/media                              # strm 输出目录的宿主路径
      - /data/docker/clouddrive2/CloudDrive:/CloudDrive:shared   # 可选：直接读挂载盘
```

访问 `http://<NAS-IP>:3000` 完成初始化。

### 3.3 配置 115 网盘登录

- **方式 A**：MoviePilot → 设置 → 网盘 → **115网盘** → 扫码或填 Cookie；
- **方式 B（推荐）**：装 **CookieCloud** 服务端 + 浏览器插件，把 115 的 Cookie 自动同步到 MoviePilot（自动刷新，免维护）。

### 3.4 启用并配置 115strm（P115StrmHelper）插件

在 MoviePilot → 插件市场安装 **115网盘STRM助手 / P115StrmHelper**，关键配置：

| 配置项 | 值 | 说明 |
|---|---|---|
| 源目录 | 115 网盘上的有声书目录（如 `/有声书/小说`） | 要生成 strm 的范围 |
| 输出目录 | `/media/115-有声书` | strm 落地位置 |
| 重定向基础地址 | `http://<NAS-IP>:3000` | **必须是能被客户端/ABS 访问到的地址**（局域网 IP 或域名） |
| 生成方式 | 目录同步（增量） | 新增书自动生成 |

**生成的 `.strm` 文件内容**形如：

```
http://<NAS-IP>:3000/api/v1/plugin/P115StrmHelper/redirect_url?pickcode=<115_pickcode>&file_id=<file_id>
```

- `pickcode` / `file_id` 是 115 文件标识；
- 访问该地址时，MoviePilot 返回 **HTTP 302**，`Location` 指向 115 CDN 的真实直链（带时效签名）。

### 3.5 生成并验证

```bash
cat "/media/115-有声书/小说/某书/第0135集.strm"
# 输出应为上面的 redirect_url

curl -sI "http://<NAS-IP>:3000/api/v1/plugin/P115StrmHelper/redirect_url?pickcode=xxx&file_id=xxx" | grep -i location
# 应返回 302 + 115 CDN 的 Location
```

> ⚠️ **坑**：115 对部分文件（API 上传的 m4a/mp3）最终响应会带 `Content-Disposition: attachment`，部分播放器（iOS AVPlayer）会拒播。这一层由下一步的 Audiobookshelf 代理剥离。

---

## 四、部署二：Audiobookshelf 302strm（入库有声书）

**目标**：用「魔改版 Audiobookshelf」把上一步的 `.strm` 目录当有声书库入库；播放时后台解析 302 并流式代理，同时提供 WMA→AAC 转码缓存与本地化。

### 4.1 镜像与目录结构

```yaml
services:
  audiobookshelf-strm302:
    image: ghcr.io/2222221029/audiobookshelf-strm:latest   # 302strm 魔改镜像
    container_name: audiobookshelf-strm302
    restart: unless-stopped
    ports:
      - "13378:80"
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - /data/docker/Audiobookshelf-strm/config:/config
      - /data/docker/Audiobookshelf-strm/metadata:/metadata
      - /media/115-有声书:/audiobooks:ro              # ① strm 库（只读）
      - /media/115-有声书-local:/audiobooks-local:ro  # ② 本地化镜像库（只读，秒播优先读这里）
      - /data/docker/Audiobookshelf-strm/patches:/app/server/patches  # ③ 补丁（bind mount）
```

> 客户端访问地址：`http://<NAS-IP>:13378/audiobookshelf`

### 4.2 打补丁（核心）

魔改层由两个补丁构成，缺一不可：

| 补丁 | 部署方式 | 作用 |
|---|---|---|
| **strmUtils.js** | **bind mount**（`patches/strmUtils.js`），改完 `docker restart` 生效 | .strm 解析、302 跟随、Range 代理、剥离 attachment、AAC 转码缓存、窗口本地化排队 |
| **LibraryItemController.js** | **非挂载 → 必须 `docker cp` 进容器** | 在 `getLibraryFile` 开头挂钩，命中 `.strm` 时交给 strmUtils 处理 |

**LibraryItemController.js 部署坑（重要）**：

```bash
scp LibraryItemController.js root@<NAS-IP>:/tmp/
ssh root@<NAS-IP> "docker cp /tmp/LibraryItemController.js audiobookshelf-strm302:/app/server/controllers/ && docker restart audiobookshelf-strm302"
```

并保留一份 `patches/LibraryItemController.js.patched` 供镜像重建时复用。

### 4.3 魔改功能说明

1. **`.strm` 代理播放**：客户端请求某集文件时，服务端读取 `.strm` → 请求 MoviePilot 的 `redirect_url` → 跟随 302 拿到 115 CDN 直链 → **流式代理**返回（支持 HTTP Range，剥离 `Content-Disposition`）。
2. **WMA → AAC 单集转码缓存**：iOS 不能解码 WMA。接口 `GET /api/items/:id/file/:ino?transcoded=1` 用 ffmpeg 把该集转成 AAC（`.m4a`，128k，faststart），缓存到 `/metadata/transcode-cache/{itemId}/{hash}.m4a`（生成一次复用；支持 Range）。实测：首次约 30s，二次约 80ms。
3. **窗口本地化排队**：播放命中未本地化文件时，把「当前集 + 后 5 集」加入本地化队列（见第五步）。

### 4.4 入库

1. 打开 `http://<NAS-IP>:13378/audiobookshelf`，管理员账号登录；
2. 新建媒体库，类型「有声书」，路径选 `/audiobooks/小说`（或 `/audiobooks/评书`）；
3. 触发扫描等待入库（`.strm` 会作为音轨导入）；**不要**把本地镜像目录也建库（会产生重复条目）。

### 4.5 验证

```bash
docker logs -f audiobookshelf-strm302 2>&1 | grep STRM-PLAY
# mode=local(本地镜像) / mode=aac-cache live|serve|gen / 直连
```

---

## 五、部署三：CloudDrive2（缓存有声书）

**目标**：把 115 网盘挂载成本地文件系统，实现「**有声书本地化缓存**」——把正在听的书提前落到 NAS 本地盘，播放秒开、稳定、断网可听。

### 5.1 部署 CloudDrive2

```yaml
services:
  clouddrive2:
    image: cloudnas/clouddrive2:latest
    container_name: clouddrive2
    restart: unless-stopped
    privileged: true
    environment:
      - TZ=Asia/Shanghai
      - CLOUDDRIVE_HOME=/Config
    volumes:
      - /data/docker/clouddrive2/Config:/Config
      - /data/docker/clouddrive2/CloudDrive:/CloudDrive:shared
    ports:
      - "19798:19798"
```

Web UI 登录 115 账号，把 115 网盘挂载到 `/CloudDrive/115`，即在 NAS 上得到本地路径 `/data/docker/clouddrive2/CloudDrive/115/...`（可直接当普通文件夹读写，读时按需从 115 下载并缓存）。

### 5.2 三种用途

1. **作为 strm 源**：MoviePilot 的 115strm 可基于该挂载生成/校验。
2. **作为本地化源**：把 115 上的有声书文件复制到本地镜像目录。
3. **作为转码数据源**：Audiobookshelf 的 WMA→AAC 转码从这里取原始文件。

### 5.3 本地化镜像（缓存机制）

- **镜像目录**：`/media/115-有声书-local`（已只读挂进 ABS 的 `/audiobooks-local`）。
- **窗口本地化脚本** `localize.sh`：把指定书的「当前集 + 后 N 集（默认 5）」从 CloudDrive2 复制到镜像目录，并**保留多级子目录结构**。
- **自动守护** `autolocalize.sh`：消费服务端播放时排队的本地化任务；建议加入 `@reboot` 开机自启。
- ABS 播放时**优先读 `/audiobooks-local`**（命中即 `mode=local`，本地磁盘读取，毫秒级）。

```bash
./localize.sh --window "小说/某书" "第0101集" 5   # 当前集起 + 后 5 集
```

### 5.4 验证

```bash
ls -R "/media/115-有声书-local/小说/某书" | head
# 服务端日志出现 mode=local 即命中本地镜像
```

---

## 六、客户端 EchoShelf（iOS）

### 下载安装（iOS 16+）

- **直接下载 IPA**：[Releases](https://github.com/zzqiuzhen/haven/releases) —— 未签名，需自签安装：
  - **Sideloadly / 爱思助手**：拖入 IPA，用 Apple ID 签名安装
  - **TrollStore**（若系统支持）：分享 IPA 给 TrollStore 直接安装
  - AltStore / LiveContainer 同理

### 功能

- 连接任意 Audiobookshelf 服务端（v2.36+ 兼容，支持子路径反代，如 `/audiobookshelf`）
- **服务器地址**：主地址 + 可选「内网地址」，连接家庭 WiFi 时**自动切换内网**、否则走外网
- 发现页：继续收听 / 聆听数据 / 最新入库 / 我的分类 / 多书库入口
- 书库：分类切换、排序、彩色搜索入口、封面网格、缓存角标
- 搜索：跨书库按**书名 / 作者 / 演播**模糊匹配 + 最近搜索历史
- 书籍详情：封面模糊背景、章节分组（每 100 章）、章节级缓存状态、书签、**长按编辑书名/作者**（本机覆盖，锁屏同步）
- 播放器：倍速 0.5x–3.0x（按书记忆）、定时关闭（含「播完本章」）、跳过片头/片尾、快进快退、章节切换、锁屏/后台播放
- 离线缓存：自动缓存后续 N 章 + 手动批量缓存，本地缓存优先播放（秒开），完整性校验
- 自定义分类：把书归入探险/科幻/悬疑等自定义分类
- 进度同步：每 30 秒 / 暂停时 / 切章时同步到服务端，与网页端无缝续听

### 快速起播做了什么

1. **打开书即预热**：进详情页就对续播章节发 `Range: 0-1` 请求，让服务端提前完成 MoviePilot → 115 的 302 解析并缓存直链。
2. **极速直连（默认开）**：播放时直接跟随 302 拉到 115 CDN（免 NAS 中转带宽），失败自动回退服务端代理。
3. **超前预取**：播放中自动预热并下载后续章节到本地；已缓存章节秒开。
4. **失败自动降级**：直连失败 → 代理；代理失败提示重试，不卡死。
5. **WMA 自动转码**：音轨无 codec 元数据（`.strm` 占位）时保守按需转码，保证可播 + 可缓存秒播。

> 实测（外网）：起播首字节约 0.4–0.7s；已缓存章节 <0.2s。

### 构建

- 本地：`flutter pub get && flutter analyze`
- 云端：推送 `main` 分支后 GitHub Actions（macos-14）自动产出**未签名 IPA**（Actions → Artifacts）

---

## 七、路径 / 端口速查

| 用途 | 路径 / 地址 |
|---|---|
| strm 有声书库 | `/media/115-有声书`（→ 容器 `/audiobooks`） |
| 本地化镜像库 | `/media/115-有声书-local`（→ `/audiobooks-local`） |
| CloudDrive2 挂载 | `/data/docker/clouddrive2/CloudDrive` |
| ABS 部署目录（config/patches） | `/data/docker/Audiobookshelf-strm/` |
| 转码缓存 | 容器内 `/metadata/transcode-cache/` |
| MoviePilot | `http://<NAS-IP>:3000` |
| Audiobookshelf | `http://<NAS-IP>:13378/audiobookshelf` |
| CloudDrive2 | `http://<NAS-IP>:19798` |

---

## 八、常见问题排查

| 现象 | 原因与处理 |
|---|---|
| 播放报 **-11828 无法打开** | 115 CDN 对该文件返回 `Content-Disposition: attachment`，AVPlayer 拒播；走服务端代理（会剥离该头） |
| 报 **-1004 无法连接服务器** | 手机不在家网、直连 MoviePilot 不可达；客户端首播前有 1.5s 封顶探测，不可达自动走服务端；建议配好内网地址 |
| 家里 WiFi 登录不上、流量能上 | 服务器地址用了公网域名、家里路由 NAT 回环/DNS 拦截；改用 Tailscale 地址或登录页填内网地址自动切换 |
| **已缓存却不秒播**/一直缓冲 | ① 该书的音轨 `.strm` 无 codec 元数据、实为 WMA 时，客户端会保守按转码处理；② 检查服务端日志是否 `mode=local` |
| 书签删不掉、刷新又回来 | ABS 书签按**浮点秒**存储，删除必须用精确秒数（取整会匹配不上） |
| 搜不到作者/演播 | ABS 搜索接口只按书名匹配；客户端已加本地兜底，按书名/作者/演播模糊扫全库 |
| 退出登录要点两次 | 退出时需清掉**内存 token**，否则后台「停止播放」会用旧 token 重新登录 |
| 媒体库出现重复条目 | 不要同时把「镜像目录」和「strm 目录」建库 |

---

## 九、维护与升级

- **Cookie 维护**：115 Cookie 过期会导致 strm 解析失败，用 CookieCloud 自动同步并定期检查。
- **补丁升级**：`strmUtils.js` 走 patches 目录 bind mount（改完重启）；`LibraryItemController.js` 必须 `docker cp`（重建镜像后要重打）。
- **磁盘清理**：本地化镜像与转码缓存会增长，可按需清理不常听的。
- **客户端更新**：通过 GitHub Release 分发未签名 IPA，装新版覆盖即可（本机设置/缓存保留）。

---

## 许可

MIT License · 仅供个人自托管使用
