// Studio records come from the app's seed at build time. All edits stay in memory.
const $ = (id) => document.getElementById(id);
const projects = JSON.parse($("demo-projects").textContent);
const columns = ["id", "name", "category", "status", "progress", "updated_at"];
const editableColumns = columns.slice(1);
let selectedId = projects[0].id;
let queryResult = null;
let sortColumn = "id";
let sortAscending = true;

function cell(text) {
  const td = document.createElement("td");
  td.textContent = text;
  return td;
}
function currentRecord() {
  return projects.find((row) => row.id === selectedId);
}
function draftValue(key) {
  return $(`null-${key}`).checked ? null : $(`record-${key}`).value;
}
function hasChanges() {
  return editableColumns.some(
    (key) => draftValue(key) !== String(currentRecord()[key]),
  );
}
function notify(message) {
  $("demo-notice").textContent = message;
  $("demo-notice").hidden = !message;
}
function allowNavigation() {
  if (!hasChanges()) {
    notify("");
    return true;
  }
  notify("当前记录有未保存的修改，请先保存或撤销。");
  return false;
}
function compareValues(a, b) {
  // SQLite puts text values after numeric values for these demo columns.
  if (typeof a !== typeof b) return typeof a === "number" ? -1 : 1;
  return a < b ? -1 : a > b ? 1 : 0;
}
function selectRecord(id) {
  if (id === selectedId || !allowNavigation()) return;
  selectedId = id;
  loadRecord();
  renderProjects();
}
function renderProjects() {
  const term = $("project-search").value.toLocaleLowerCase();
  const visible = projects
    .filter((row) =>
      columns.some((key) =>
        String(row[key]).toLocaleLowerCase().includes(term),
      ),
    )
    .sort(
      (a, b) =>
        compareValues(a[sortColumn], b[sortColumn]) * (sortAscending ? 1 : -1),
    );
  $("project-rows").replaceChildren(
    ...visible.map((project, index) => {
      const row = document.createElement("tr");
      row.classList.toggle("selected", project.id === selectedId);
      row.append(cell(String(index + 1)));
      columns.forEach((key) => {
        const td = cell(String(project[key]));
        if (key === "name") {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "project-button";
          button.textContent = project.name;
          button.setAttribute("aria-label", `选择 ${project.name}`);
          button.setAttribute(
            "aria-pressed",
            String(project.id === selectedId),
          );
          button.addEventListener("click", () => selectRecord(project.id));
          td.replaceChildren(button);
        }
        if (key === "status") {
          const dot = document.createElement("span");
          dot.className = `status-dot ${project.status === "已完成" ? "done" : project.status === "待开始" ? "pending" : ""}`;
          dot.setAttribute("aria-hidden", "true");
          td.prepend(dot);
        }
        row.append(td);
      });
      row.addEventListener("click", (event) => {
        if (!event.target.closest("button")) selectRecord(project.id);
      });
      return row;
    }),
  );
  if (!visible.length) {
    const row = document.createElement("tr");
    const empty = cell("没有匹配的记录。试试其他关键词；筛选仅作用于当前页。");
    empty.colSpan = 7;
    row.append(empty);
    $("project-rows").append(row);
  }
  $("record-count").textContent =
    `${visible.length} 条记录 · 每页 200 条 · 第 1 页`;
  document.querySelectorAll("[data-sort]").forEach((button) => {
    button.parentElement.setAttribute(
      "aria-sort",
      button.dataset.sort === sortColumn
        ? sortAscending
          ? "ascending"
          : "descending"
        : "none",
    );
  });
}
function updateDraft() {
  const changed = hasChanges();
  $("save-record").disabled = $("undo-record").disabled = !changed;
  $("draft-indicator").textContent = changed ? "已修改" : "6 个字段";
  editableColumns.forEach((key) => {
    $(`record-${key}`).disabled = $(`null-${key}`).checked;
    $(`record-${key}`).classList.toggle(
      "modified",
      draftValue(key) !== String(currentRecord()[key]),
    );
  });
  $("save-status").textContent = changed ? "有未保存的修改" : "";
}
function createFields() {
  columns.forEach((key) => {
    const group = document.createElement("div");
    group.className = "record-field";
    const label = document.createElement("label");
    label.htmlFor = `record-${key}`;
    label.textContent = key;
    const type = document.createElement("span");
    type.className = "field-type";
    type.textContent = key === "id" || key === "progress" ? "INTEGER" : "TEXT";
    label.append(type);
    const input = document.createElement("input");
    input.id = `record-${key}`;
    input.type = "text";
    input.autocomplete = "off";
    input.setAttribute("aria-label", `字段 ${key}`);
    if (key === "progress") input.inputMode = "decimal";
    group.append(label, input);
    if (key === "id") {
      input.disabled = true;
      input.title = "主键不可直接修改";
    } else {
      const nullLabel = document.createElement("label");
      nullLabel.className = "null-option";
      const toggle = document.createElement("input");
      toggle.type = "checkbox";
      toggle.id = `null-${key}`;
      toggle.setAttribute("aria-label", `将 ${key} 设为 NULL`);
      nullLabel.append(toggle, "NULL");
      group.append(nullLabel);
      toggle.addEventListener("change", () => {
        input.value = toggle.checked ? "" : String(currentRecord()[key]);
        updateDraft();
      });
      input.addEventListener("input", updateDraft);
    }
    $("record-fields").append(group);
  });
}
function loadRecord() {
  columns.forEach((key) => {
    $(`record-${key}`).value = String(currentRecord()[key]);
  });
  editableColumns.forEach((key) => {
    $(`null-${key}`).checked = false;
  });
  updateDraft();
}
$("project-search").addEventListener("input", renderProjects);
$("record-form").addEventListener("submit", (event) => {
  event.preventDefault();
  if (!hasChanges()) return;
  const nullField = editableColumns.find((key) => draftValue(key) === null);
  if (nullField) {
    notify(
      `操作未完成：NOT NULL constraint failed: projects.${nullField}。Studio 示例表该字段不可为空，请取消 NULL 后保存。`,
    );
    return;
  }
  editableColumns.forEach((key) => {
    const value = draftValue(key);
    const numeric =
      key === "progress" &&
      value.trim() !== "" &&
      Number.isFinite(Number(value));
    currentRecord()[key] = numeric ? Number(value) : value;
  });
  loadRecord();
  renderProjects();
  notify("");
  $("save-status").textContent = "已保存到本页示例";
});
$("record-form").addEventListener("reset", (event) => {
  event.preventDefault();
  loadRecord();
  notify("");
  $("save-status").textContent = "已撤销未保存的修改";
});
createFields();
loadRecord();
renderProjects();
document.querySelectorAll("[data-sort]").forEach((button) =>
  button.addEventListener("click", () => {
    if (!allowNavigation()) return;
    sortAscending = sortColumn === button.dataset.sort ? !sortAscending : true;
    sortColumn = button.dataset.sort;
    renderProjects();
  }),
);

const tabs = Array.from(document.querySelectorAll("[role=tab]"));
function selectTab(tab) {
  if (tab.getAttribute("aria-selected") !== "true" && !allowNavigation())
    return false;
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute("aria-selected", String(selected));
    item.tabIndex = selected ? 0 : -1;
    $(item.getAttribute("aria-controls")).hidden = !selected;
  }
  return true;
}
tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectTab(tab));
  tab.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = tabs[(index + 1) % tabs.length];
    if (event.key === "ArrowLeft")
      next = tabs[(index + tabs.length - 1) % tabs.length];
    if (event.key === "Home") next = tabs[0];
    if (event.key === "End") next = tabs.at(-1);
    if (next) {
      event.preventDefault();
      if (selectTab(next)) next.focus();
    }
  });
});
function exampleResults(sorted = false) {
  const rows = projects
    .filter((row) => typeof row.progress === "string" || row.progress >= 70)
    .map(({ name, progress }) => ({ name, progress }));
  return sorted
    ? rows.sort((a, b) => compareValues(b.progress, a.progress))
    : rows;
}
function resultTable(rows) {
  const table = document.createElement("table");
  const head = document.createElement("thead");
  const header = document.createElement("tr");
  ["name", "progress"].forEach((name) => {
    const th = document.createElement("th");
    th.scope = "col";
    th.textContent = name;
    header.append(th);
  });
  head.append(header);
  const body = document.createElement("tbody");
  rows.forEach((project) => {
    const row = document.createElement("tr");
    row.append(cell(project.name), cell(String(project.progress)));
    body.append(row);
  });
  table.append(head, body);
  return table;
}
$("run-query").addEventListener("click", () => {
  queryResult = exampleResults(true);
  const count = document.createElement("p");
  count.className = "result-count";
  count.textContent = `查询结果 · ${queryResult.length} 行 · Studio 本页示例`;
  $("query-results").replaceChildren(count, resultTable(queryResult));
  $("export-csv").disabled = false;
});
$("export-csv").addEventListener("click", () => {
  if (queryResult === null) return;
  // Keep spreadsheet formula protection for the public webpage's editable demo.
  const quote = (value) => {
    const text = String(value);
    const safe = /^\s*[=+@-]/.test(text) ? `'${text}` : text;
    return `"${safe.replaceAll('"', '""')}"`;
  };
  const csv =
    "\uFEFFname,progress\r\n" +
    queryResult
      .map((row) => `${quote(row.name)},${quote(row.progress)}`)
      .join("\r\n");
  const url = URL.createObjectURL(
    new Blob([csv], { type: "text/csv;charset=utf-8" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = "TableViewer-example.csv";
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
document.addEventListener("keydown", (event) => {
  if (!(event.metaKey || event.ctrlKey) || !event.target.closest("#experience"))
    return;
  if (event.key.toLowerCase() === "s" && !$("panel-browse").hidden) {
    event.preventDefault();
    $("record-form").requestSubmit();
  }
  if (event.key === "Enter" && !$("panel-query").hidden) {
    event.preventDefault();
    $("run-query").click();
  }
});

let agentState = "pending";
function resolveOperation(approved) {
  if (agentState !== "pending") return;
  agentState = approved ? "executed" : "rejected";
  $("approve-operation").disabled = $("reject-operation").disabled = true;
  const result = approved ? exampleResults() : "用户拒绝此操作。未执行查询。";
  const disclosure = document.createElement("details");
  const summary = document.createElement("summary");
  summary.textContent = "查看本地结果（尚未发送）";
  const content = document.createElement("pre");
  content.textContent = approved ? JSON.stringify(result, null, 2) : result;
  disclosure.append(summary, content);
  const message = document.createElement("p");
  message.textContent = approved
    ? `已执行一次：${result.length} 行结果留在本页，尚未发送。`
    : result;
  const share = document.createElement("button");
  share.className = "small-button blue";
  share.textContent = "发送结果并继续";
  share.addEventListener("click", () => {
    if (agentState !== "executed" && agentState !== "rejected") return;
    agentState = "shared";
    $("agent-result").textContent = approved
      ? `模拟已发送工具结果：${result.length} 个项目达到目标进度。本页没有实际 API 调用。`
      : "模拟已将拒绝结果告知模型。本页没有执行查询，也没有实际 API 调用。";
  });
  const note = document.createElement("p");
  note.textContent = "结果目前只在本页。点击下方按钮模拟另行确认发送。";
  $("agent-result").replaceChildren(message, disclosure, note, share);
}
$("approve-operation").addEventListener("click", () => resolveOperation(true));
$("reject-operation").addEventListener("click", () => resolveOperation(false));
$("reset-agent").addEventListener("click", () => {
  agentState = "pending";
  $("agent-result").replaceChildren();
  $("approve-operation").disabled = $("reject-operation").disabled = false;
});

const dialog = $("screenshot-dialog");
const screenshots = {
  light: { file: "assets/workspace-light-zh-Hans.png", label: "浅色" },
  dark: { file: "assets/workspace-dark-zh-Hans.png", label: "深色" },
};
document.querySelectorAll("[data-appearance]").forEach((button) =>
  button.addEventListener("click", () => {
    const selected = screenshots[button.dataset.appearance];
    $("workspace-preview").src = $("dialog-screenshot").src = selected.file;
    $("workspace-preview").alt =
      `TableViewer ${selected.label}真实界面：Studio 示例数据库与记录详情`;
    $("dialog-screenshot").alt =
      `TableViewer ${selected.label}数据库工作台完整界面`;
    $("open-screenshot").setAttribute(
      "aria-label",
      `放大查看 TableViewer ${selected.label}真实界面`,
    );
    $("screenshot-caption").textContent = `真实界面 · ${selected.label}外观`;
    $("dialog-caption").textContent = `TableViewer · ${selected.label}真实界面`;
    $("original-screenshot").href = selected.file;
    document
      .querySelectorAll("[data-appearance]")
      .forEach((item) =>
        item.setAttribute("aria-pressed", String(item === button)),
      );
  }),
);
$("open-screenshot").addEventListener("click", () => {
  dialog.showModal();
  document.body.style.overflow = "hidden";
});
$("close-screenshot").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target !== dialog) return;
  const r = dialog.getBoundingClientRect();
  if (
    event.clientX < r.left ||
    event.clientX > r.right ||
    event.clientY < r.top ||
    event.clientY > r.bottom
  )
    dialog.close();
});
dialog.addEventListener("close", () => {
  document.body.style.overflow = "";
});
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
if ("IntersectionObserver" in window && !reducedMotion.matches) {
  document.documentElement.classList.add("motion-ready");
  const observer = new IntersectionObserver(
    (entries) =>
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          observer.unobserve(entry.target);
        }
      }),
    { threshold: 0.08 },
  );
  document
    .querySelectorAll(".reveal")
    .forEach((element) => observer.observe(element));
}
