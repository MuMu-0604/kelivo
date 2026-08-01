# HTML rendering sample

这是一段普通 Markdown 文本，用来确认原有渲染仍然正常。

- 普通列表项
- **加粗文本**
- `inline_code()`

<p>这是一个 HTML 段落。</p>

<p>同一个 HTML 段落里的第一行<br>这里应该换到第二行。</p>

这里是普通 Markdown 链接：[Kelivo GitHub](https://github.com/kelivo/Kelivo)

这里是 HTML 链接：<a href="https://example.com">Example HTML link</a>

<details>
<summary>点击展开：次要信息</summary>

这里是折叠内容的第一段。

- details 内的 Markdown 列表
- details 内的 **加粗文本**
- details 内的 HTML 链接：<a href="https://example.com/docs">Example docs</a>

<p>details 内的 HTML 段落<br>这里应该在折叠块内换行。</p>

```dart
void main() {
  print('code block inside details');
}
```
</details>

<details open>
<summary>默认展开：open 属性</summary>

这一块带有 `open` 属性，初始状态应该直接展开。
</details>

结束段落。
