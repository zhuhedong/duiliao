# duiliao_app · V2.0

Duiliao 运营随身端：开奖、号码属性、共识、源评级、采集执行、AI 报告和本地通知。

V2.0 follows the Aurora Glass mobile design in [`../app-design`](../app-design):
the default dark indigo canvas, translucent cards, ambient aurora background and
direct role-aware bottom navigation are shared by the native client and the
reviewable HTML prototype.

数据源、服务监控、共识排行榜、记录、跳码助手、玩法目录和系统设置等设计稿次级页面
均已接入“更多功能”和个人中心快捷入口，并复用真实采集、共识、评级和本地缓存接口。

账号由 Web 后台创建，APP 没有注册入口。构建和签名流程见
[`docs/app_release.md`](../docs/app_release.md)。
