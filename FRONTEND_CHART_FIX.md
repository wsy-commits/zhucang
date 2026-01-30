# 前端图表修复指南

## 🔍 问题诊断

图表显示 "Waiting for data..." 的原因：

1. ✅ 代码已修复（`loadCandles` 和 `loadTrades` 已实现）
2. ❌ 前端可能缓存了旧代码
3. ❌ 需要强制刷新

---

## 🚀 解决方案

### 方案 1：强制刷新（推荐）

1. **打开浏览器开发者工具**
   - Windows/Linux: 按 `F12`
   - Mac: 按 `Cmd + Option + I`

2. **右键点击刷新按钮**
   - 选择 "清空缓存并硬性重新加载"
   - 或按 `Ctrl + Shift + R` (Windows/Linux)
   - 或按 `Cmd + Shift + R` (Mac)

3. **检查控制台**
   - 切换到 "Console" 标签
   - 查找 `[loadCandles]` 日志
   - 应该看到：`[loadCandles] Generated mock candles: 101`

### 方案 2：重启前端服务器

```bash
# 1. 停止当前前端
# 在前端终端按 Ctrl+C

# 2. 重新启动
cd /mnt/c/Users/a/Desktop/perpm-course2/frontend
pnpm dev

# 3. 打开浏览器
# http://localhost:3000
```

### 方案 3：清除浏览器缓存

Chrome/Edge:
1. 打开设置 → 隐私和安全
2. 点击 "清除浏览数据"
3. 选择 "缓存的图片和文件"
4. 点击 "清除数据"

---

## 🐛 调试步骤

### 1. 检查控制台日志

打开控制台（F12），应该看到：

```
[loadCandles] Generated mock candles: 101
[loadTrades] Generated mock trades: 20
```

如果没看到这些日志，说明代码没有加载。

### 2. 检查网络请求

1. 打开控制台（F12）
2. 切换到 "Network" 标签
3. 刷新页面
4. 查找失败的请求（红色）

### 3. 检查错误信息

在控制台中查找红色错误消息，例如：

```
Uncaught TypeError: ...
ReferenceError: ...
```

---

## ✅ 验证图表是否正常

加载成功后应该看到：

### K 线图表
- ✅ 显示 100 根蜡烛图
- ✅ 蓝色 = 上涨，粉色 = 下跌
- ✅ 可以缩放和拖动
- ✅ 鼠标悬停显示价格

### Recent Trades
- ✅ 显示 20 笔交易
- ✅ 包含价格、数量、时间
- ✅ 绿色 = 买单，红色 = 卖单

---

## 🔧 如果仍然不显示

### 检查代码版本

在控制台输入：

```javascript
// 检查 store 是否有 loadCandles 实现
window.location.reload()
```

### 手动测试数据生成

在控制台输入：

```javascript
// 访问 store 并手动调用
const store = window.__EXCHANGE_STORE__;
if (store) {
  store.loadCandles();
  console.log('Candles:', store.candles.length);
}
```

### 最终方案：重新构建

```bash
cd /mnt/c/Users/a/Desktop/perpm-course2/frontend

# 清理缓存
rm -rf node_modules/.vite

# 重新启动
pnpm dev
```

---

## 📊 预期效果

修复后应该看到：

```
┌─────────────────────────────────┐
│  ETH/USD    [15m] [1h] [4h] [1d] │
│                                  │
│    ╱╲    ╱╲╱╲    ╱╲            │
│   ╱  ╲  ╱  ╱  ╲  ╱  ╲           │
│  ╱    ╲╱    ╲╱    ╲╱            │
│                                  │
│  💡 K 线图表（100 根蜡烛）        │
└─────────────────────────────────┘
```

---

**如果以上方案都不行，请发送控制台截图或错误信息！** 🐛
