# h3z 官网设置指南

## 🌐 GitHub Pages 设置

### 1. 启用 GitHub Pages

1. 进入 GitHub 仓库页面
2. 点击 **Settings** 标签
3. 在左侧菜单中找到 **Pages**
4. 在 **Source** 部分选择：
   - **Deploy from a branch**
   - Branch: `main`
   - Folder: `/docs`
5. 点击 **Save**

### 2. 访问网站

设置完成后，网站将在以下地址可用：
- **GitHub Pages URL**: `https://dg0230.github.io/h3z`
- **自定义域名** (可选): `h3z.dev` (需要配置 DNS)

### 3. 自动部署

- 每当 `docs/` 目录中的文件发生更改时，GitHub Actions 会自动重新部署网站
- 部署状态可以在 **Actions** 标签中查看

## 🎨 网站特性

### 设计亮点
- **现代化设计**: 参考 h3.dev 的简洁专业风格
- **响应式布局**: 完美适配桌面、平板和手机
- **交互动画**: 平滑滚动、悬停效果和动画
- **代码高亮**: Zig 代码语法高亮显示

### 核心部分
1. **Hero 区域**: 框架介绍和实时代码示例
2. **特性展示**: 零依赖、内存安全、高性能等
3. **快速开始**: 4步安装指南
4. **页脚**: 社区链接和资源

### 技术特性
- **SEO 优化**: 完整的 meta 标签和结构化数据
- **社交分享**: Open Graph 和 Twitter Card 支持
- **性能优化**: 轻量级、快速加载
- **无障碍**: 符合 WCAG 标准

## 📁 文件结构

```
docs/
├── index.html          # 主页面
├── styles.css          # CSS 样式
├── script.js           # JavaScript 功能
├── favicon.svg         # 网站图标
├── _config.yml         # GitHub Pages 配置
└── README.md           # 网站文档
```

## 🛠️ 本地开发

要在本地运行网站：

```bash
# 进入 docs 目录
cd docs

# 使用 Python 启动服务器
python -m http.server 8000

# 或使用 Node.js
npx http-server

# 访问 http://localhost:8000
```

## 🔧 自定义配置

### 修改内容
- 编辑 `docs/index.html` 更新页面内容
- 修改 `docs/styles.css` 调整样式
- 更新 `docs/script.js` 添加交互功能

### 配置域名
如果有自定义域名 (如 h3z.dev)：

1. 在 `docs/` 目录创建 `CNAME` 文件
2. 文件内容为域名: `h3z.dev`
3. 配置 DNS 记录指向 GitHub Pages

### 分析和监控
可以添加：
- Google Analytics
- GitHub 统计
- 性能监控

## 📊 SEO 优化

网站已包含：
- 完整的 meta 标签
- Open Graph 标签
- Twitter Card 支持
- 结构化数据
- 语义化 HTML
- 快速加载优化

## 🚀 部署流程

1. **开发**: 在 `docs/` 目录中修改文件
2. **测试**: 本地测试确保功能正常
3. **提交**: `git add docs/ && git commit -m "update website"`
4. **推送**: `git push origin main`
5. **自动部署**: GitHub Actions 自动部署到 Pages

## 📈 性能指标

目标性能指标：
- **Lighthouse 分数**: 90+ (所有类别)
- **首次内容绘制**: < 1.5s
- **最大内容绘制**: < 2.5s
- **累积布局偏移**: < 0.1

## 🤝 贡献指南

要为网站做贡献：

1. Fork 仓库
2. 创建功能分支
3. 在 `docs/` 目录中进行更改
4. 本地测试
5. 提交 Pull Request

## 📞 支持

如果遇到问题：
- 查看 GitHub Actions 日志
- 检查 GitHub Pages 设置
- 参考 GitHub Pages 文档
- 在仓库中创建 Issue

---

**网站地址**: https://dg0230.github.io/h3z  
**仓库地址**: https://github.com/dg0230/h3z  
**框架文档**: 查看 README.md
