import Foundation

extension HTTPStatusCatalog {
    public static let entries: [HTTPStatusEntry] = [
        // 1xx 信息
        HTTPStatusEntry(code: 100, name: "Continue", meaning: "继续", detail: "服务器已收到请求头，告诉客户端可以继续发送请求体（常用于上传大文件前的确认），避免白白传输会被拒绝的数据。", family: 1),
        HTTPStatusEntry(code: 101, name: "Switching Protocols", meaning: "切换协议", detail: "服务器同意按客户端要求切换协议，最常见于 HTTP 升级为 WebSocket 连接时的握手。", family: 1),
        HTTPStatusEntry(code: 102, name: "Processing", meaning: "处理中", detail: "WebDAV 扩展：服务器已收到请求并在处理中，但还没有结果，用来防止客户端等待超时。", family: 1),
        HTTPStatusEntry(code: 103, name: "Early Hints", meaning: "早期提示", detail: "在最终响应前先发送部分响应头（如 Link），让浏览器提前预加载 CSS、字体等资源，加快页面打开速度。", family: 1),

        // 2xx 成功
        HTTPStatusEntry(code: 200, name: "OK", meaning: "请求成功", detail: "最常见的成功响应。GET 时响应体是请求的资源，POST/PUT 时是操作结果。", family: 2),
        HTTPStatusEntry(code: 201, name: "Created", meaning: "已创建资源", detail: "请求成功并创建了新资源（如新用户、新订单），响应头 Location 通常指向新资源的地址。", family: 2),
        HTTPStatusEntry(code: 202, name: "Accepted", meaning: "已接受", detail: "请求已被接受但尚未处理完成，常用于异步任务（如排队的后台作业），不保证最终一定成功。", family: 2),
        HTTPStatusEntry(code: 203, name: "Non-Authoritative Information", meaning: "非权威信息", detail: "请求成功，但返回的内容被中间代理修改过，不一定与源服务器完全一致。", family: 2),
        HTTPStatusEntry(code: 204, name: "No Content", meaning: "成功但无内容", detail: "请求成功，但没有响应体。常见于删除操作或表单保存后，页面无需刷新。", family: 2),
        HTTPStatusEntry(code: 205, name: "Reset Content", meaning: "重置内容", detail: "请求成功，并要求客户端清空刚提交的表单，方便用户输入新内容。", family: 2),
        HTTPStatusEntry(code: 206, name: "Partial Content", meaning: "部分内容", detail: "服务器只返回了资源的一部分（按 Range 请求），用于断点续传和视频流的分段加载。", family: 2),
        HTTPStatusEntry(code: 207, name: "Multi-Status", meaning: "多状态", detail: "WebDAV：响应体（XML）中包含多个资源各自的状态码，一次请求可报告多个结果。", family: 2),
        HTTPStatusEntry(code: 208, name: "Already Reported", meaning: "已报告", detail: "WebDAV：在 207 响应中避免重复列出同一资源的状态。", family: 2),
        HTTPStatusEntry(code: 226, name: "IM Used", meaning: "已使用实例操作", detail: "服务器返回的是对资源做增量更新的结果（delta 编码），只传变化部分以节省带宽。", family: 2),

        // 3xx 重定向
        HTTPStatusEntry(code: 300, name: "Multiple Choices", meaning: "多种选择", detail: "请求的资源有多个可选版本（如不同格式或语言），由客户端或用户选择其一。", family: 3),
        HTTPStatusEntry(code: 301, name: "Moved Permanently", meaning: "永久重定向", detail: "资源已永久迁移到 Location 指向的新地址，浏览器和搜索引擎会更新链接。适合永久修改 URL。", family: 3),
        HTTPStatusEntry(code: 302, name: "Found", meaning: "临时重定向", detail: "资源暂时在另一个地址，客户端这次去新地址，但以后仍用原地址。", family: 3),
        HTTPStatusEntry(code: 303, name: "See Other", meaning: "查看其他位置", detail: "让客户端用 GET 去访问另一个地址，常用于表单提交后跳转结果页，防止刷新重复提交。", family: 3),
        HTTPStatusEntry(code: 304, name: "Not Modified", meaning: "资源未修改", detail: "资源自上次缓存以来没有变化，服务器不返回内容，浏览器直接用缓存，节省带宽。", family: 3),
        HTTPStatusEntry(code: 305, name: "Use Proxy", meaning: "使用代理", detail: "已废弃。原本要求通过指定代理访问资源，因安全问题被弃用。", family: 3),
        HTTPStatusEntry(code: 307, name: "Temporary Redirect", meaning: "临时重定向", detail: "类似 302，但保证请求方法不变（POST 仍是 POST）。", family: 3),
        HTTPStatusEntry(code: 308, name: "Permanent Redirect", meaning: "永久重定向", detail: "类似 301，但保证请求方法不变，适合永久迁移会接收 POST 的接口。", family: 3),

        // 4xx 客户端错误
        HTTPStatusEntry(code: 400, name: "Bad Request", meaning: "请求语法错误", detail: "请求格式有问题（语法错误、JSON 非法、缺少字段），需要客户端修正后重试。", family: 4),
        HTTPStatusEntry(code: 401, name: "Unauthorized", meaning: "未认证", detail: "名为未授权，实为未认证：没提供凭证或凭证无效。带 WWW-Authenticate 头说明如何登录。", family: 4),
        HTTPStatusEntry(code: 402, name: "Payment Required", meaning: "需要付费", detail: "保留状态码，部分 API 用它表示需要付费套餐或额度才能继续。", family: 4),
        HTTPStatusEntry(code: 403, name: "Forbidden", meaning: "拒绝访问", detail: "已认证但没有权限访问该资源。与 401 不同，重新登录也没用。", family: 4),
        HTTPStatusEntry(code: 404, name: "Not Found", meaning: "资源不存在", detail: "服务器上没有该地址的资源，可能被删、被移动或从未存在。最常见的网页错误。", family: 4),
        HTTPStatusEntry(code: 405, name: "Method Not Allowed", meaning: "方法不允许", detail: "地址存在但不支持该请求方法（如只接受 GET 的接口收到 POST），响应头 Allow 列出允许的方法。", family: 4),
        HTTPStatusEntry(code: 406, name: "Not Acceptable", meaning: "不可接受", detail: "服务器无法返回符合 Accept 头要求的格式（如向只支持 JSON 的接口要 XML）。", family: 4),
        HTTPStatusEntry(code: 407, name: "Proxy Authentication Required", meaning: "需要代理认证", detail: "类似 401，但需要先通过代理服务器的身份验证。", family: 4),
        HTTPStatusEntry(code: 408, name: "Request Timeout", meaning: "请求超时", detail: "客户端发送请求太慢，服务器等待超时主动断开，可重试。", family: 4),
        HTTPStatusEntry(code: 409, name: "Conflict", meaning: "请求冲突", detail: "请求与资源当前状态冲突（如注册已被占用的用户名、基于过期版本的编辑），需解决后重试。", family: 4),
        HTTPStatusEntry(code: 410, name: "Gone", meaning: "已永久删除", detail: "类似 404，但服务器明确知道资源已被永久删除，告诉客户端别再请求。", family: 4),
        HTTPStatusEntry(code: 411, name: "Length Required", meaning: "需要长度", detail: "服务器要求请求带 Content-Length 头声明请求体大小。", family: 4),
        HTTPStatusEntry(code: 412, name: "Precondition Failed", meaning: "前置条件失败", detail: "请求头中的条件（如 If-Match）未满足，常用于乐观锁防止覆盖他人修改。", family: 4),
        HTTPStatusEntry(code: 413, name: "Content Too Large", meaning: "请求内容过大", detail: "请求内容超过服务器愿意或能够处理的大小，常见于上传文件或请求体超过限制；若限制是临时的，响应可能通过 Retry-After 告知重试时间。", family: 4),
        HTTPStatusEntry(code: 414, name: "URI Too Long", meaning: "地址过长", detail: "请求 URL 太长，通常是查询字符串塞了太多数据，应改用请求体（如改成 POST）。", family: 4),
        HTTPStatusEntry(code: 415, name: "Unsupported Media Type", meaning: "不支持的媒体类型", detail: "请求体格式服务器不支持（如向只读 JSON 的接口发 XML），需设置正确的 Content-Type。", family: 4),
        HTTPStatusEntry(code: 416, name: "Range Not Satisfiable", meaning: "范围无法满足", detail: "请求的字节范围超出文件实际大小，常见于断点续传偏移信息过期。", family: 4),
        HTTPStatusEntry(code: 417, name: "Expectation Failed", meaning: "期望失败", detail: "服务器无法满足请求 Expect 头的要求（通常是 100-continue）。", family: 4),
        HTTPStatusEntry(code: 418, name: "I'm a Teapot", meaning: "我是茶壶", detail: "当前 IANA 注册表标为 unused（未使用）；它源自 RFC 2324 的愚人节 HTCPCP 茶壶玩笑，不代表现行通用 HTTP 语义。", family: 4),
        HTTPStatusEntry(code: 421, name: "Misdirected Request", meaning: "请求定向错误", detail: "请求被发到无法响应它的服务器，常见于 HTTP/2 连接复用，客户端可换新连接重试。", family: 4),
        HTTPStatusEntry(code: 422, name: "Unprocessable Content", meaning: "无法处理的内容", detail: "服务器能识别请求内容类型且语法正确，但无法处理其中的指令或语义；例如 JSON/XML 格式正确，但字段值或业务规则不满足。", family: 4),
        HTTPStatusEntry(code: 423, name: "Locked", meaning: "已锁定", detail: "WebDAV：目标资源被锁定，需先解锁才能修改。", family: 4),
        HTTPStatusEntry(code: 424, name: "Failed Dependency", meaning: "依赖失败", detail: "WebDAV：因为它依赖的前一个请求失败，所以本请求也无法执行。", family: 4),
        HTTPStatusEntry(code: 425, name: "Too Early", meaning: "过早", detail: "服务器不愿处理可能被重放的请求（与 TLS 1.3 的 0-RTT 早期数据相关）。", family: 4),
        HTTPStatusEntry(code: 426, name: "Upgrade Required", meaning: "需要升级", detail: "服务器拒绝当前协议，要求客户端升级（如改用 TLS 或更新的 HTTP 版本）。", family: 4),
        HTTPStatusEntry(code: 428, name: "Precondition Required", meaning: "需要前置条件", detail: "服务器要求请求带条件头（如 If-Match），防止两个客户端互相覆盖修改。", family: 4),
        HTTPStatusEntry(code: 429, name: "Too Many Requests", meaning: "请求过于频繁", detail: "限流：客户端在一段时间内请求过多，响应头 Retry-After 通常说明多久后可重试。", family: 4),
        HTTPStatusEntry(code: 431, name: "Request Header Fields Too Large", meaning: "请求头过大", detail: "请求头太大超出服务器限制，常因 Cookie 过大，减小后重试。", family: 4),
        HTTPStatusEntry(code: 451, name: "Unavailable For Legal Reasons", meaning: "因法律原因不可用", detail: "因法律要求（如法院命令或审查）被屏蔽。编号致敬小说《华氏 451》。", family: 4),

        // 5xx 服务器错误
        HTTPStatusEntry(code: 500, name: "Internal Server Error", meaning: "服务器内部错误", detail: "服务器端兜底错误，通常是未处理的异常或 bug，客户端没做错，需服务器修复。", family: 5),
        HTTPStatusEntry(code: 501, name: "Not Implemented", meaning: "未实现", detail: "服务器不支持该请求方法或功能。与 405 不同，是功能根本没做，而非这里不允许。", family: 5),
        HTTPStatusEntry(code: 502, name: "Bad Gateway", meaning: "网关错误", detail: "服务器作为网关/反向代理，从上游服务器收到了无效响应，常见于后端服务挂了。", family: 5),
        HTTPStatusEntry(code: 503, name: "Service Unavailable", meaning: "服务不可用", detail: "服务器暂时无法处理（过载或维护中），是临时状态，Retry-After 可能说明恢复时间。", family: 5),
        HTTPStatusEntry(code: 504, name: "Gateway Timeout", meaning: "网关超时", detail: "服务器作为网关/代理，等待上游服务器响应超时，通常是后端太慢或无响应。", family: 5),
        HTTPStatusEntry(code: 505, name: "HTTP Version Not Supported", meaning: "不支持的 HTTP 版本", detail: "服务器不支持请求使用的 HTTP 协议版本，现代环境少见。", family: 5),
        HTTPStatusEntry(code: 506, name: "Variant Also Negotiates", meaning: "变体协商错误", detail: "服务器内容协商配置出错导致循环引用，属服务器配置错误。", family: 5),
        HTTPStatusEntry(code: 507, name: "Insufficient Storage", meaning: "存储空间不足", detail: "WebDAV：服务器没有足够空间完成请求，通常是磁盘满了。", family: 5),
        HTTPStatusEntry(code: 508, name: "Loop Detected", meaning: "检测到循环", detail: "WebDAV：处理请求时（如深度复制）陷入死循环被中止。", family: 5),
        HTTPStatusEntry(code: 510, name: "Not Extended", meaning: "未扩展", detail: "当前 IANA 注册表标为 obsolete（已废弃）；它源自 RFC 2774 的 HTTP 扩展框架，表示请求未满足扩展策略，不应作为普通现行状态使用。", family: 5),
        HTTPStatusEntry(code: 511, name: "Network Authentication Required", meaning: "需要网络认证", detail: "强制门户（酒店、机场、咖啡馆 Wi-Fi 登录页）返回，需先登录才能上网。", family: 5),
    ]
}
