export const USER_STATUS_LABEL: Record<string, string> = {
  active: "正常运行",
  pending: "待验证",
  suspended: "已停用",
  banned: "已封禁",
  deleted: "已注销",
};

export const USER_ROLE_LABEL: Record<string, string> = {
  user: "普通用户",
  staff: "技术员工",
  admin: "超级管理员",
};

export const USER_SOURCE_LABEL: Record<string, string> = {
  web: "Web 网页端",
  ios: "iOS 客户端",
  android: "Android 客户端",
  api: "开放接口",
};

export const USER_STATUS_DESC: Record<string, string> = {
  active: "鉴权正常 · 具备当前角色的会话权限",
  pending: "账号尚未完成验证",
  suspended: "账号已停用，部分操作不可用",
  banned: "账号已封禁",
  deleted: "账号已注销",
};

export const USER_SOURCE_DESC: Record<string, string> = {
  web: "从 Web 控制台注册",
  ios: "从 iOS 客户端注册",
  android: "从 Android 客户端注册",
  api: "通过开放接口注册",
};

export const USER_ROLE_DESC: Record<string, string> = {
  user: "标准业务查询权限",
  staff: "可执行采集与对照写操作",
  admin: "系统最高控制权限",
};

export function userStatusTone(status: string): "success" | "warning" | "danger" {
  if (status === "active") return "success";
  if (status === "pending") return "warning";
  return "danger";
}
