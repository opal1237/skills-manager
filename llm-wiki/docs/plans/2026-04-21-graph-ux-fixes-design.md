# 设计：水彩图谱 5 项 UX 修复

生成于 2026-04-21 · 分支 main · 模式：Builder（既有功能打磨）
状态：DRAFT · v3（已吸收 /plan-ceo-review 11 项 + /plan-eng-review 9 项反馈）

## 问题陈述

水彩风格交互图谱（v3.0，PR #17 引入）在实际使用中暴露 5 个 UX 问题：

1. **抽屉布局失衡**：小屏下"相邻节点"区无滚动也无高度限制，相邻过多时会把"知识区"挤压甚至完全遮挡
2. **卡片文字溢出**：节点卡片宽度硬封顶 180px，但长标签不做截断，文字溢出卡片边界
3. **小地图常驻**：右上角小地图固定占用 180×130 空间，无法折叠隐藏
4. **工具按钮功能不可见**：右上角三个图标按钮（重排 / 居中 / Tweaks）没有可见标签，原生 `title` tooltip 延迟且丑，首次用户不知作用
5. **项目地址位置隐蔽**：`llm-wiki-skill` GitHub 链接藏在 footer 右侧 11px 小字，用户难以发现

## 核心原则（来自用户）

- **知识区为主，相邻节点为辅**：问题 1 的分配策略要体现这一点，知识区永远拿到大多数空间
- **用户使用角度优先**：所有方案以首次使用体验为准绳，不以"代码最省事"为准绳

## 约束

- 只改 `templates/graph-styles/wash/header.html` 和 `templates/graph-styles/wash/graph-wash.js`
- 不改图谱数据结构、构建脚本、或节点布局算法
- 保持水彩（wash）视觉主题与现有 Tweaks 变体的兼容性
- 回归测试必须全部通过（`tests/graph-html-*.regression-*.sh`）

## 前置共识（Premises）

1. ✅ 五个问题都是既有功能打磨，不涉及图谱架构改动
2. ✅ 五个一起做，不分批
3. ✅ 每条方案的取舍以"用户使用角度"为准

## 推荐方案（逐条）

### 问题 1：抽屉改为"主-辅"双区独立滚动 + 相邻节点可折叠

**根因**：`.drawer-inner` 用 flexbox 但 `.drawer-neighbors` 没有 `max-height` 也没有独立 `overflow`，`flex: 1` 的 `.drawer-body` 因 flex-basis=0 无力对抗按内容撑开的邻居区。

**方案（header.html）**：

```css
.drawer-inner {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.drawer-body {
  flex: 1 1 0;           /* 知识区为主，吃掉剩余空间 */
  overflow-y: auto;
  min-height: 0;         /* 允许在 flex 中正确收缩 */
}
.drawer-neighbors {
  flex-shrink: 0;
  max-height: 35vh;       /* 上限约屏幕高的 1/3，不抢主区 */
  overflow-y: auto;       /* 自己内部滚 */
  border-top: 1px dashed var(--paper-ink-faint);
}
.drawer-neighbors[data-collapsed="1"] {
  max-height: 40px;       /* 折叠后只剩标题条 */
  overflow: hidden;
}
.drawer-neighbors h4 {
  cursor: pointer;        /* 点标题触发折叠 */
  user-select: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.drawer-neighbors h4::after {
  content: "⌃";           /* 折叠指示箭头 */
  font-family: var(--font-hand);
  transition: transform 180ms;
}
.drawer-neighbors[data-collapsed="1"] h4::after {
  transform: rotate(180deg);
}
```

**方案（graph-wash.js，约 25 行新增）**：

```js
// 注意：drawer 的 DOM 骨架（.drawer-neighbors > h4 + #nb-list）在 header.html 里是静态的，
// openDetailDrawer() 每次只清空 #nb-list 的 innerHTML，不会重建 h4。
// 所以这里的监听器在 init 时绑定一次即可，不会泄漏。

// 标题改为可聚焦按钮语义 + aria-expanded 状态
const h4 = drawerNeighbors.querySelector("h4");
h4.setAttribute("tabindex", "0");
h4.setAttribute("role", "button");

function applyNeighborsCollapsed(collapsed) {
  drawerNeighbors.setAttribute("data-collapsed", collapsed ? "1" : "0");
  h4.setAttribute("aria-expanded", collapsed ? "false" : "true");
}

// 初始化：默认展开（首次用户能直接看到邻居内容）
const savedCollapsed = safeLocalStorage.get("wiki-neighbors-collapsed") === "1";
applyNeighborsCollapsed(savedCollapsed);

function toggleNeighbors() {
  const next = drawerNeighbors.getAttribute("data-collapsed") !== "1";
  applyNeighborsCollapsed(next);
  safeLocalStorage.set("wiki-neighbors-collapsed", next ? "1" : "0");
}

h4.addEventListener("click", toggleNeighbors);
h4.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    toggleNeighbors();
  }
});
```

**默认状态：展开**。理由：首次用户需要看到邻居列表才能发现折叠这个功能；如果默认折叠就成了隐藏功能，与"用户使用角度"原则冲突。

**交付行为**：
- 邻居 0~5 条：按内容高度展开，不浪费空间
- 邻居 20+ 条：容器最多占 35vh，内部滚动条
- 用户想专注阅读：点击或回车/空格键一键折叠"相邻节点"标题
- 折叠偏好跨会话持久（localStorage 不可用时只影响本次会话，见"共享工具"一节）

---

### 问题 2：卡片标签截断 + SVG 原生 tooltip 显示全名

**根因**：`cardDims()` 用 `Math.min(180, w + pad)` 封顶卡片宽度，但 `.text()` 直接写完整 label，SVG 文字不自动截断。

**方案（graph-wash.js）**：

新增工具函数 `truncateLabel(label, maxWidth)`：

```js
// 用 Intl.Segmenter 遍历字素簇（grapheme cluster），不是 code point。
// 这样 ZWJ 连接的 emoji（如 👨‍👩‍👧‍👦）被当作一个整体处理，不会截在中间产生半个表情。
// 现代浏览器全支持，零新依赖。
const labelSegmenter = new Intl.Segmenter("zh", { granularity: "grapheme" });

function truncateLabel(label, maxWidth) {
  if (!label || typeof label !== "string") {
    console.warn("[wiki] truncateLabel: invalid input", label);
    return { text: "", truncated: false };
  }

  // 与 cardDims 一致的字符宽度估算
  const charWidth = g => /[一-鿿]/.test(g) ? 15 : 8.5;
  const pad = 22;
  const ellipsis = "…";
  const ellipsisW = 8;

  const graphemes = Array.from(labelSegmenter.segment(label), s => s.segment);

  let totalW = 0;
  for (const g of graphemes) totalW += charWidth(g);
  if (totalW + pad <= maxWidth) return { text: label, truncated: false };

  let out = "";
  let w = 0;
  for (const g of graphemes) {
    const cw = charWidth(g);
    if (w + cw + ellipsisW + pad > maxWidth) break;
    out += g;
    w += cw;
  }
  return { text: out + ellipsis, truncated: true };
}
```

在 `renderNodes()` 卡片渲染分支里：

```js
const { text: displayLabel, truncated } = truncateLabel(d.label || d.id, 180);
gg.append("text").attr("class", "node-label node-label--in")
  .attr("text-anchor", "middle").attr("dy", "0.35em")
  .text(displayLabel);
// SVG 原生 tooltip，hover 时浏览器显示完整名
if (truncated) {
  gg.append("title").text(d.label || d.id);
}
```

**为什么用 SVG `<title>`，而不是像问题 4 那样做自定义 tooltip**：

这里看似与问题 4"批判原生 tooltip 延迟"矛盾，其实定位不同：

- **问题 4 的工具按钮**：tooltip 是**主入口**——用户必须看到标签文字才知道按钮能做什么，1 秒延迟直接伤首次体验，所以换成可见文字 + 自定义 tooltip。
- **问题 2 的节点标签**：`<title>` 只是**辅助补充**——用户查看完整名的**主入口**是点击节点进入抽屉（抽屉里永远显示完整 label）。hover 看到完整名只是"能查也行、不查也能用"的便利，1 秒延迟可以接受。

这样选的额外收益：零依赖、零新 CSS、无障碍读屏天然兼容、不会和问题 4 的 `data-tip` hover 样式互相干扰。

**已知局限**（详见"已知局限"一节）：`charWidth` 对 emoji、全角标点、阿拉伯数字宽度估算不够精确，极端情况下可能截断偏多或偏少 1~2 字。MVP 可接受，有需要再精化。

**交付行为**：
- 短标签不受影响
- 长标签显示前 N 字 + "…"，鼠标悬停 1 秒左右浏览器弹完整名
- 点击节点抽屉里永远是完整名（不变）

---

### 问题 3：小地图可折叠（带持久化）

**方案（header.html）**：

小地图容器加折叠按钮和折叠态样式：

```html
<!-- 当前 header.html:1035 的 .minimap div 没有 id，需要在这次改动中补上 id="minimap" -->
<div class="minimap" id="minimap" data-collapsed="0">
  <div class="minimap__label">小地图</div>
  <button class="minimap__toggle" id="minimap-toggle"
          aria-label="折叠小地图" aria-expanded="true"
          data-tip="折叠/展开小地图">⌄</button>
  <svg id="minimap-svg"></svg>
</div>
```

```css
.minimap {
  /* 既有规则不变 */
  transition: width 220ms, height 220ms;
}
.minimap[data-collapsed="1"] {
  width: 88px;
  height: 22px;
  overflow: hidden;
}
.minimap[data-collapsed="1"] #minimap-svg {
  display: none;
}
.minimap[data-collapsed="1"] .minimap__label {
  top: 2px; left: 6px;
  background: transparent;
}
.minimap__toggle {
  position: absolute;
  top: 2px; right: 4px;
  width: 22px; height: 20px;
  background: transparent;
  border: none;
  color: var(--paper-ink-dim);
  font-size: 14px;
  cursor: pointer;
  z-index: 3;
  transition: transform 180ms;
}
.minimap[data-collapsed="1"] .minimap__toggle {
  transform: rotate(180deg);
  right: 2px;
}
```

**方案（graph-wash.js）**：

```js
const minimap = document.getElementById("minimap");
const toggleBtn = document.getElementById("minimap-toggle");

function applyMinimapCollapsed(collapsed) {
  minimap.setAttribute("data-collapsed", collapsed ? "1" : "0");
  toggleBtn.setAttribute("aria-expanded", collapsed ? "false" : "true");
  toggleBtn.setAttribute("aria-label", collapsed ? "展开小地图" : "折叠小地图");
}

applyMinimapCollapsed(safeLocalStorage.get("wiki-minimap-collapsed") === "1");

toggleBtn.addEventListener("click", (e) => {
  e.stopPropagation();
  const next = minimap.getAttribute("data-collapsed") !== "1";
  applyMinimapCollapsed(next);
  safeLocalStorage.set("wiki-minimap-collapsed", next ? "1" : "0");
});
```

**交付行为**：
- 默认展开（首次使用直接看到功能）
- 点击右上小箭头折叠成一条 88×22 的标签条
- 折叠状态下仍能看到"小地图"标签，用户知道它在哪、怎么展开
- 设置跨会话持久

---

### 问题 4：工具按钮改为"图标 + 文字"组合，窄屏退化为图标 + 自定义 tooltip

**根因**：原生 `title` tooltip 延迟 ~1 秒出现、视觉不统一、首次用户完全无法预判功能。

**方案（header.html）**：

按钮从纯 icon 改为 icon + 文字（基准态）：

```html
<button class="iconbtn iconbtn--labeled" id="btn-refit" data-tip="重新布置节点">
  <svg>...</svg>
  <span class="iconbtn__text">重排</span>
</button>
<button class="iconbtn iconbtn--labeled" id="btn-fit" data-tip="适应画布 · 回到居中">
  <svg>...</svg>
  <span class="iconbtn__text">居中</span>
</button>
<button class="iconbtn iconbtn--labeled" id="btn-tweaks" data-tip="视觉设置">
  <svg>...</svg>
  <span class="iconbtn__text">设置</span>
</button>
```

```css
.iconbtn--labeled {
  width: auto;
  padding: 0 12px;
  gap: 6px;
  font-family: var(--font-ui);
  font-size: 13px;
  border-radius: 18px;
}
.iconbtn__text {
  color: var(--paper-ink-dim);
  line-height: 1;
}
.iconbtn--labeled:hover .iconbtn__text { color: var(--paper-ink); }

/* 自定义即时 tooltip（无延迟） */
[data-tip] { position: relative; }
[data-tip]:hover::after,
[data-tip]:focus-visible::after {
  content: attr(data-tip);
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  max-width: min(240px, calc(100vw - 24px));  /* 极窄屏 fallback：不超出视口 */
  white-space: normal;                         /* 允许窄屏换行，不做无限拉长 */
  word-break: break-word;
  padding: 5px 10px;
  background: var(--paper-ink);
  color: #fdf7e6;
  font-family: var(--font-ui);
  font-size: 11px;
  border-radius: 4px;
  box-shadow: 1px 2px 0 rgba(43,38,32,0.15);
  z-index: 40;
  pointer-events: none;
  animation: tip-in 140ms ease-out;
}
/* 极窄屏（<480px）右边三个按钮贴边，tooltip 贴右会被裁：改为相对画面靠右但不越界 */
@media (max-width: 480px) {
  [data-tip]:hover::after,
  [data-tip]:focus-visible::after {
    right: auto;
    left: 0;
    max-width: calc(100vw - 16px);
  }
}
@keyframes tip-in {
  from { opacity: 0; transform: translateY(-3px); }
  to   { opacity: 1; transform: translateY(0); }
}
@media (prefers-reduced-motion: reduce) {
  [data-tip]:hover::after,
  [data-tip]:focus-visible::after { animation: none; }
}

/* 窄屏：回到纯图标模式，但保留 data-tip 做补充说明 */
@media (max-width: 900px) {
  .iconbtn--labeled { width: 34px; padding: 0; }
  .iconbtn__text { display: none; }
}
```

**Tweaks 面板未来扩展点**：在 Tweaks 面板的 JS 初始化处加一行 `// TODO: neighbor-area-max-height slider (35vh default)` 占位注释，标记将来可加"邻居区上限"滑块的位置。零实现代价，给后续迭代留锚点。

**为什么 "图标+文字" 常驻是首选**：
- 首次用户零学习成本，一眼看懂
- 不强迫用户 hover 才能发现功能（tooltip 本质是把可见 UI 藏起来的妥协）
- 宽屏空间完全够用（三个按钮总宽不到 220px）
- 窄屏自动退化为原来的纯图标 + 自定义 tooltip

**交付行为**：
- ≥900px：按钮展示 icon + 文字（重排 / 居中 / 设置）
- <900px：退化为圆形图标按钮，hover 立即弹自定义 tooltip（无延迟，视觉统一）
- 移除不必要的原生 `title` 属性（避免与 data-tip 双弹）

---

### 问题 5：项目地址提升到左上角品牌区

**方案（header.html）**：

把 `.brand__mark`（"llm-wiki" 小圆点 logo）包成指向仓库的 `<a>`：

```html
<header class="brand">
  <a class="brand__mark" href="https://github.com/sdyckjq-lab/llm-wiki-skill"
     target="_blank" rel="noopener"
     data-tip="查看 llm-wiki 项目 · GitHub">
    llm-wiki
  </a>
  <div class="brand__title" id="wiki-title">__WIKI_TITLE__</div>
  <!-- ... -->
</header>
```

```css
.brand__mark {
  /* 既有规则保留（包括基线 transform: rotate(-0.6deg)）+ 下面几条 */
  text-decoration: none;
  color: var(--paper-ink);
  transition: transform 200ms;
}
/* 注意：基线已经 rotate(-0.6deg)，hover 再多转 -0.6deg 到 -1.2deg，
   视觉效果是"更偏斜"而不是"转正"。这才是"轻微抖动提示可点"的正确方向。 */
.brand__mark:hover,
.brand__mark:focus-visible {
  transform: rotate(-1.2deg) translateY(-1px);
  outline: none;
}
.brand__mark:focus-visible {
  box-shadow: 0 0 0 2px var(--paper-ink-dim);
  border-radius: 4px;
}
.brand__mark:hover::before {
  box-shadow: 2px 3px 0 rgba(0,0,0,0.2);  /* 水彩圆点阴影加深 */
}
@media (prefers-reduced-motion: reduce) {
  .brand__mark { transition: none; }
  .brand__mark:hover,
  .brand__mark:focus-visible { transform: rotate(-0.6deg); }  /* 保持基线，不动 */
}
```

**footer 里重复的 "generated by llm-wiki" 链接**：保留。理由：
- footer 是开发者习惯找归因链接的位置，删掉反而出乎意料
- brand 区提升是"把入口变醒目"，不是"把原入口删掉"
- 两处链接都指向同一 URL，不会造成迷惑

**未来路径依赖提醒**（NICE-TO-HAVE）：现在 "brand → GitHub" 的语义是"品牌即项目地址"。将来如果 llm-wiki 新增一个概览/索引页（例如 "所有知识库首页"），这块就会变成语义冲突点——brand 该指向项目仓库还是本地概览页？届时建议：brand 改指向概览页，项目仓库退回 footer；或者 brand 保留指仓库、另起一个"首页"按钮。本轮不做决策，仅标记这是一个**未来 UX 决策点**。

**交付行为**：
- 左上角 "llm-wiki" 可点，hover / 键盘聚焦都有明显反馈（轻微旋转 + 阴影加深 + focus ring），符合水彩手绘风格
- `prefers-reduced-motion` 用户看到的是静态反馈，不旋转
- 点击新标签页打开仓库

---

## 共享工具：safeLocalStorage

问题 1 和问题 3 都依赖 localStorage 做偏好持久化。但 localStorage 存在已知失败模式：Safari 隐私模式抛异常、第三方 cookie 禁用、存储配额满、企业环境策略限制。**直接写 `localStorage.getItem/setItem` 会让这些用户一进来就白屏**。

在 `graph-wash.js` 的 IIFE 顶部（state 声明之后、任何读写 localStorage 的初始化之前，约文件前 20 行内）加一个模块级 helper，所有 localStorage 调用都走它：

```js
const safeLocalStorage = {
  get(key) {
    try { return localStorage.getItem(key); }
    catch (err) { console.warn("[wiki] localStorage.get failed:", key, err); return null; }
  },
  set(key, value) {
    try { localStorage.setItem(key, value); }
    catch (err) { console.warn("[wiki] localStorage.set failed:", key, err); /* swallow */ }
  },
};
```

**失败降级行为**：读失败 → 返回 null → 走默认值（邻居展开、小地图展开）；写失败 → 静默 warn，本次会话内折叠/展开仍然工作，只是跨会话不持久。用户感知：功能全部可用，只是"这次点的折叠，下次刷新恢复默认"。可接受。

---

## 无障碍（a11y）要求

三处必须做：

1. **相邻节点折叠标题**（问题 1）：`<h4>` 加 `tabindex="0"` + `role="button"` + `aria-expanded` 状态 + Enter/Space 键盘触发。代码已写在问题 1 方案里。
2. **小地图折叠按钮**（问题 3）：`aria-expanded` 反映当前状态；`aria-label` 随状态切换（"折叠小地图" / "展开小地图"）。代码已写在问题 3 方案里。
3. **品牌链接动效**（问题 5）：`@media (prefers-reduced-motion: reduce)` 覆盖 hover 旋转，改为静态视觉反馈；同时加 `:focus-visible` 焦点环保证键盘可达。代码已写在问题 5 方案里。

**验收方法**：
- 只用键盘（Tab / Enter / Space）能完成：打开抽屉 → 折叠邻居 → 折叠小地图 → 跳转 brand 链接
- macOS 系统设置里开"减少动态效果"后，刷新页面，brand hover 没有旋转、tooltip 没有淡入动画

---

## 已知局限

1. **`truncateLabel` 字符宽度估算不精确**：`charWidth` 用一个简单正则区分 CJK 和 Latin，但以下情况会偏差：
   - Emoji（通常双宽度，但不在 CJK 正则范围内）
   - 全角标点（"，。！？"）估算为 CJK 宽度，基本准确；半角标点估算为 Latin 宽度，也基本准确；但全角空格、半角空格、破折号有偏差
   - 阿拉伯数字、泰文、阿拉伯文、印地文均走 Latin 8.5px，实际宽度可能偏小或偏大

   **影响范围**：极端情况下卡片里可能多截或少截 1~2 字，或 "…" 紧贴边缘。MVP 可接受。
   **缓解方案**（不在本轮做）：用 `getComputedTextLength()` 在渲染后实测宽度再截断，代价是两次布局。如将来出现大量非 CJK/Latin 标签，再做精化。

   **注意（v3 已修）**：截断点**不会**在 ZWJ 连接的 emoji 中间落下（如 👨‍👩‍👧‍👦 不会被拆成"👨"）——通过 `Intl.Segmenter` 按字素簇遍历，不是 code point。宽度估算是独立问题。

2. **`localStorage` 跨会话持久在部分环境不可用**（Safari 隐私模式、禁第三方 cookie、企业策略）：已通过 `safeLocalStorage` 降级，本次会话功能完整，只是刷新会回默认。
   **用户可感知症状**：在这类环境下用户可能疑惑"我昨天折叠了邻居，今天怎么又展开了？"。本轮不加 UI 提示（避免首次使用就被打扰），只在 README / CHANGELOG 中提一句"折叠偏好依赖 localStorage"。

---

## NOT in scope（显式延后）

本 PR 不做的事，各配一行理由：

- **`zoom-ctrl` +/- 按钮的 tooltip 统一**：两个按钮仍用原生 `title`（1 秒延迟）。理由：scope 只收用户明确投诉的三个右上按钮；zoom 按钮本身图标就是通用符号（+/−），首次用户能猜，延迟 tooltip 影响小。下一轮 UX 批次再统一。
- **`truncateLabel` 宽度估算完美化**（非 CJK/Latin 脚本的精确宽度）：用 `getComputedTextLength()` 实测是标准解法，但代价是两次布局。目前知识库没有大量阿拉伯/泰文节点，MVP 可接受偏差。记为 Known Limitation。
- **引入 JS 单测框架**（bun test / vitest / node:test）：跨项目决策，不该藏在 UX 修复 PR 里。`truncateLabel` 等纯函数本轮通过多长度 golden fixture 间接覆盖。建议加入 TODOS.md 作为独立决策。
- **fixture 自动 diff 白名单工具**：理想但超范围。本轮通过"每个问题独立 commit + 每次只看小 diff"的纪律缓解。
- **Tweaks 面板 "邻居区上限 (vh)" 滑块**：零代价占位注释已加，真正实现延后。
- **`localStorage` 失败时的用户 UI 提示**：首次使用就弹"你的浏览器不支持偏好持久化"太吵，延后。
- **概览/首页路由出现后 brand 链接的重新指向**：长期决策点，v2 已标记，本轮不做。

---

## 可观察性

加几处 `console.warn`，用户遇到问题时方便把浏览器控制台日志发回给我们定位：

1. `safeLocalStorage.get/set` 的 catch 分支（已在工具函数里）
2. `truncateLabel` 拿到空 label 或非字符串时：`console.warn("[wiki] truncateLabel: invalid input", label)`
3. 小地图 SVG 初始化失败时（defensive）：`console.warn("[wiki] minimap render failed:", err)`

不做上报、不做埋点，纯本地 warn。零新依赖。

---

## 备选方案（记录以便回头对照）

### 问题 1 的 B 方案：统一滚动
知识 + 相邻节点塞进同一个滚动容器。优点：改动最小。缺点：查邻居要先滚过整篇知识。**否决理由**：违反"相邻节点为辅"（它占据了知识区末尾，反而成了必经之路）。

### 问题 4 的 A 方案：纯图标 + 自定义 tooltip
只加 tooltip 不加可见文字。**否决理由**：违反"用户使用角度"——首次进入仍然需要 hover 三次才能摸清，工具栏功能不该藏起来。

### 问题 5 的 C 方案：footer 链接删除
避免重复。**否决理由**：开发者习惯看 footer，保留冗余对体验无损。

---

## 成功标准

1. **问题 1**：相邻节点 30 条时，知识区仍能看到至少 65% 屏幕高度的内容；折叠后知识区占满
2. **问题 2**：节点 label 长度 ≥ 20 字时，卡片边缘无文字溢出；hover 能看到完整名
3. **问题 3**：折叠小地图后右上角只剩一条 88×22 的标签；刷新页面后保持折叠
4. **问题 4**：宽屏（≥900px）三个按钮文字可见；窄屏按钮 hover ≤150ms 内弹出自定义 tooltip
5. **问题 5**：左上角 llm-wiki 字样可点、hover 有视觉反馈、点击跳转到 GitHub

---

## 测试与回归清单

**测试框架选择**：项目现有 `tests/graph-html-*.regression-*.sh` 全部是 shell + DOM 字符串断言 + golden fixture diff 风格。**不**引入 JS 单测框架（bun test / vitest）——那是跨项目决策，不该藏在本 UX 修复 PR 里。JS 纯函数（`truncateLabel` / `safeLocalStorage`）的覆盖通过**多标签长度的 golden fixture** 间接验证。如果后续发现这层太粗，再做独立 PR 引入单测框架（见"NOT in scope"）。

**分步 fixture 更新（避免一次性大 diff）**：每完成一个问题的 commit 后，就跑一次 `scripts/build-graph-html.sh` 生成 HTML → 用 `diff tests/expected/graph-interactive-basic.html <(生成的 HTML)` 看 diff → **确认 diff 行数和本 commit 描述吻合**（如问题 5 应该只看到 brand 变 a、新增 CSS；问题 4 应该只看到按钮结构 + tooltip CSS）→ 覆盖 fixture。这样每次眼睛只看 1-2 处变化，遗漏无关回归的概率大大降低。

### 改动完成后的验证清单：

1. **跑现有回归**（每个 commit 后都跑一遍）：
   - `tests/graph-html-mobile.regression-1.sh`（小屏下布局——问题 1 核心回归）
   - `tests/graph-html-styles.regression-1.sh`（样式一致性——问题 4/5 会影响；依赖分步 fixture 更新）
   - `tests/graph-html-search.regression-1.sh`（搜索功能——不应受影响）

2. **新增回归（本 PR 必做）**：
   - `tests/graph-html-drawer-neighbors.regression-1.sh`：fixture 含 30+ 邻居，断言知识区高度占比 ≥ 60%，断言 h4 有 `aria-expanded` 属性
   - `tests/graph-html-long-label.regression-1.sh`：fixture 含多种长度标签（5/15/25 字 CJK、5/15/25 字 Latin、混合、含 emoji），断言长标签 DOM 中 label 带 `…`、带 `<title>` 元素；短标签不带
   - `tests/graph-html-minimap.regression-1.sh`：断言 `#minimap` 容器有 id、`#minimap-toggle` 存在且有 `aria-expanded`
   - `tests/graph-html-brand-link.regression-1.sh`：断言 `.brand__mark` 是 `<a href="https://github.com/sdyckjq-lab/llm-wiki-skill"` 且 `rel="noopener"`，断言 CSS 包含 `:focus-visible`
   - `tests/graph-html-a11y.regression-1.sh`：断言 CSS 包含 `@media (prefers-reduced-motion: reduce)` 规则，断言 h4/minimap-toggle 都有正确的 role + tabindex + aria-\* 属性组合

3. **手动验收清单**（codex 终端跑 ingest → graph 后）：
   - 小屏（<600px 宽度）打开抽屉，相邻 > 20 时知识仍可读
   - 长标签节点卡片视觉无溢出，长标签中含 ZWJ emoji（如 👨‍👩‍👧‍👦）截断后不出现半个表情
   - 小地图折叠 → 刷新 → 仍折叠
   - 三个工具按钮文字可见
   - 左上 llm-wiki 点击跳转正确
   - 只用键盘完成：Tab 到邻居标题 → Enter 折叠 → Tab 到小地图 toggle → Enter 折叠 → Tab 到 brand 链接 → Enter 跳转
   - 系统开"减少动态效果"后，brand hover 不转（只保留基线 rotate -0.6deg）、tooltip 不淡入
   - **Safari 隐私模式**打开页面，点折叠邻居，刷新——确认没报错；本次会话能折叠但刷新回默认展开（localStorage 配额失败降级）

---

## 分步实施建议（可选，留给实施阶段决定）

如果一次性改完压力太大，建议顺序：

0. **先加 `safeLocalStorage` helper**（5 行，纯新增，无视觉影响）→ 问题 1/3 都要用，放最前面一次搞定
1. **问题 5**（最小改动，10 行内，low risk）→ 先试水流程；同步更新金标准 fixture
2. **问题 2**（纯 JS，无全局 CSS 冲突）
3. **问题 3**（小地图独立模块）
4. **问题 4**（涉及工具栏重排，需回归样式测试）
5. **✋ 人工验收卡点**：跑 `scripts/build-graph-html.sh` 生成 HTML，浏览器打开看一眼右上角三个按钮 + tooltip + 小地图折叠 + brand 链接都正常，再继续。问题 4 和问题 1 都大改 header.html 的 CSS，中间隔一次验收能把样式回归问题提前抓出来，比混在一个大 commit 里查容易。
6. **问题 1**（最核心，涉及抽屉整体布局，最后做保证其他验收时抽屉可用）
7. **收尾**：更新 fixture → 跑全部回归 → 更新 CHANGELOG / README

每一步单独 commit，符合项目 `CLAUDE.md` 的分步提交规则。

---

## 分发计划

不涉及新产物分发：这个 skill 用户通过 `install.sh` 安装后直接得到新模板。按项目 `CLAUDE.md` 的推送前规则：

- 更新 `CHANGELOG.md`（新增版本条目 —— 按当前 v3.0 递增到 v3.1）
- 更新 `README.md` 功能列表（"抽屉可折叠邻居 / 节点标签截断 / 小地图可折叠 / 工具按钮带文字 / 品牌区可点击"）
- 推送前按三层测试规则跑一遍（第一层 Claude Code 自动跑；第二/三层 codex 终端手动跑工作流）

---

## 开放问题

1. 问题 4 中按钮文字选 "重排 / 居中 / 设置" 还是更长的 "重新布置 / 适应画布 / 视觉设置"？短版省空间、视觉更紧凑；长版更清晰。**默认：短版**，如果用户反馈不清楚再调。
2. 问题 1 的 `max-height: 35vh` 是否合适？可能需要在真实使用中微调（30vh / 40vh）。初版用 35vh，留 Tweaks 面板里加一个"邻居区上限"的滑块做后续迭代。**默认：暂不加滑块**，保持方案最小。
3. 问题 5 的 hover 效果旋转角度（-1.2deg）是否过头？水彩风格整体就有手绘抖动，再加旋转可能叠加。**默认：保守做 -0.4deg**，之后按视觉反馈调。

---

## 下一步

- 用户确认这份文档 → 实施阶段（建议新开分支 `fix/graph-ux-batch-2026-04`，按"分步实施建议"顺序 commit）
- 或用户先选择优先级/方案调整 → 回到本文档迭代

实施入口推荐：直接告诉我"按这个方案做"，我就开分支动手。如果想再看一份独立视角的审查，可以调用 `/plan-eng-review`。

---

## v3 修订记录（2026-04-21）

v3 吸收 `/plan-eng-review` 的 9 条工程反馈：

**CRITICAL（🔴 4 条）**
1. **brand hover 旋转方向修正**：`.brand__mark` 基线已经 `rotate(-0.6deg)`，hover 用 `-0.4deg` 会"转正"，和"抖动提示可点"意图相反。改为 `rotate(-1.2deg) translateY(-1px)`（基线 +0.6deg 偏斜）。问题 5 方案已修。
2. **`truncateLabel` 字素簇遍历**：`for...of` 按 code point 遍历，ZWJ 连接的 emoji（如 👨‍👩‍👧‍👦）会被截成"半个表情 + …"。改用 `Intl.Segmenter` 按 grapheme cluster 遍历，现代浏览器全支持，零依赖。问题 2 方案已修。
3. **测试策略**：项目现有 `tests/graph-html-*.regression-*.sh` 全是 shell + fixture 风格，没有 JS 单测。本 PR **不**引入单测框架（跨项目决策），`truncateLabel` / `safeLocalStorage` 通过多长度 golden fixture 间接覆盖。已在"测试与回归清单"显式说明，并加入 TODOS 候选。
4. **fixture 分步更新**：原方案"一次性更新 + 人工 diff"太脆弱，7 处独立变化容易漏看。改为"每个问题独立 commit 后都刷新 fixture"，每次只看 1-2 处小 diff。已在"测试与回归清单"改段落。

**WARNING（🟡 4 条）**
5. **`#minimap` 容器缺 id**：现有 `header.html:1035` 的 `.minimap` 没有 id，plan 的 JS 会拿到 null。已在问题 3 HTML 示例补注释强调这一点。
6. **`zoom-ctrl` tooltip 显式延后**：右下 +/- 按钮仍用原生 `title`，本轮不动。已加入 "NOT in scope"。
7. **`safeLocalStorage` 声明位置明确**：写明"IIFE 顶部、state 声明之后、任何 localStorage 读写之前（前 20 行内）"。已在"共享工具"段落补。
8. **a11y 自动化回归**：新增 `tests/graph-html-a11y.regression-1.sh` + minimap + brand-link 三个 shell 脚本，自动断言 role/tabindex/aria-\* 属性 + `prefers-reduced-motion` CSS 规则存在。已加入"测试与回归清单"。

**NICE-TO-HAVE（🟢 1 条）**
9. **h4 持久性注释**：加一行说明"openDetailDrawer() 只清空 nb-list，h4 是静态的，监听器绑定一次即可"，避免未来误读。已在问题 1 JS 代码块顶部加注释。

**相关新增 NOT in scope 条目**（源自 #6、#3、#8 等）：zoom-ctrl tooltip、单测框架引入、fixture 自动 diff 工具、truncateLabel 宽度完美化、localStorage 失败 UI 提示。

---

## v2 修订记录（2026-04-21）

v2 吸收 `/plan-ceo-review` 审核的 11 条反馈：

**CRITICAL（7 条必修）**
1. 问题 2 的 SVG `<title>` 定位为"辅助 tooltip"，与问题 4 的"tooltip 作主入口"不矛盾，已在问题 2 段落显式说明。
2. 问题 5 的 `brand__mark` 从 `<div>` 改 `<a>` 会让 `tests/expected/graph-interactive-basic.html` 金标准失效，已在"测试与回归清单"加入同步更新步骤。
3. 所有 localStorage 调用改走 `safeLocalStorage` helper（try/catch 降级），已新增"共享工具"一节。
4. 问题 1 邻居折叠默认状态明确为**展开**（首次用户才能发现功能），已在问题 1 段落标注。
5. 三处 a11y 修正：邻居标题键盘可达 + aria-expanded、小地图 toggle aria-expanded、brand 链接 prefers-reduced-motion + focus-visible，已新增"无障碍要求"一节并融入各方案。
6. `data-tip` 极窄屏 viewport 溢出 fallback（<480px 改靠左对齐 + max-width），已加入问题 4 CSS。
7. 实施顺序在问题 4 和问题 1 之间插入人工验收卡点，已更新"分步实施建议"。

**WARNING（1 条）**
8. `truncateLabel` 对 emoji / 全角标点 / 非拉丁字符宽度估算的已知局限，已新增"已知局限"一节。

**NICE-TO-HAVE（3 条）**
9. "brand → GitHub" 语义的未来路径依赖（概览页/首页出现时），已在问题 5 段落加了未来决策点提醒。
10. Tweaks 面板"邻居区上限"滑块的占位注释，已在问题 4 段落末尾说明。
11. `safeLocalStorage` 失败、`truncateLabel` 异常输入、小地图渲染失败的 `console.warn`，已新增"可观察性"一节。
