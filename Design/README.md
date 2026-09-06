# App icon / 应用图标

The editable source is `TableViewer/Resources/AppIcon.icon`, an Icon Composer document compiled directly by Xcode. `IconLayers/` holds SVG copies of the five original layers: connections, table, header, columns, and focused cell.

可编辑源文件为 `TableViewer/Resources/AppIcon.icon`，由 Xcode 直接编译。`IconLayers/` 保存连接背板、表格视窗、字段表头、记录与焦点单元格五层原创 SVG 副本。修改图标后请同步矢量副本。

Run `./script/export_icons.sh` to generate appearance and size previews in `Design/Previews/`. These generated files and earlier design explorations stay outside Git. Original artwork is covered by the repository's MIT license.

References: [Icon Composer](https://developer.apple.com/icon-composer/), [Creating an app icon](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
