// All interactive data lives in this page. No database or AI network requests.
const projects = [
  {
    id: 1,
    name: "Aperture",
    status: "active",
    progress: 72,
    description: "为摄影师提供更直观的浏览与筛选体验。",
  },
  {
    id: 2,
    name: "Forma",
    status: "active",
    progress: 86,
    description: "一套保持清晰与一致的界面设计系统。",
  },
  {
    id: 3,
    name: "Quiet Hours",
    status: "done",
    progress: 100,
    description: "留一点安静的时间，把注意力还给创作。",
  },
  {
    id: 4,
    name: "Monograph",
    status: "active",
    progress: 48,
    description: "记录值得留下的想法与作品。",
  },
];
const $ = (id) => document.getElementById(id);
let selectedId = 1;
let queryResult = null;

function cell(text) {
  const td = document.createElement("td");
  td.textContent = text;
  return td;
}

function renderProjects() {
  const term = $("project-search").value.trim().toLocaleLowerCase();
  const visible = projects.filter((project) =>
    project.name.toLocaleLowerCase().includes(term),
  );
  $("project-rows").replaceChildren(
    ...visible.map((project) => {
      const row = document.createElement("tr");
      row.classList.toggle("selected", project.id === selectedId);
      const name = cell("");
      const button = document.createElement("button");
      button.type = "button";
      button.className = "project-button";
      button.textContent = project.name;
      button.setAttribute("aria-label", `编辑 ${project.name}`);
      button.setAttribute("aria-pressed", String(project.id === selectedId));
      button.addEventListener("click", () => {
        selectedId = project.id;
        loadRecord();
        renderProjects();
        $("record-name").focus({ preventScroll: true });
      });
      name.append(button);
      const status = cell(project.status === "done" ? "已完成" : "进行中");
      const dot = document.createElement("span");
      dot.className = `status-dot ${project.status === "done" ? "done" : ""}`;
      dot.setAttribute("aria-hidden", "true");
      status.prepend(dot);
      const progress = cell("");
      const progressText = document.createElement("div");
      progressText.className = "progress-cell";
      progressText.textContent = `${project.progress}%`;
      const track = document.createElement("span");
      track.className = "progress-track";
      track.setAttribute("aria-hidden", "true");
      const fill = document.createElement("i");
      fill.style.width = `${project.progress}%`;
      track.append(fill);
      progressText.append(track);
      progress.append(progressText);
      row.append(name, status, progress);
      return row;
    }),
  );
  if (!visible.length) {
    const row = document.createElement("tr");
    const empty = cell("没有匹配项目，请尝试其他名称。");
    empty.colSpan = 3;
    row.append(empty);
    $("project-rows").append(row);
  }
  $("record-count").textContent = `${visible.length} 条记录 · 点击项目以编辑`;
}

function loadRecord() {
  const project = projects.find((item) => item.id === selectedId);
  $("record-name").value = project.name;
  $("record-status").value = project.status;
  $("record-progress").value = project.progress;
  $("progress-value").textContent = `${project.progress}%`;
  $("record-description").value = project.description;
  $("save-status").textContent = "";
}

$("project-search").addEventListener("input", renderProjects);
$("record-progress").addEventListener("input", () => {
  $("progress-value").textContent = `${$("record-progress").value}%`;
  $("save-status").textContent = "尚未保存";
});
$("record-name").addEventListener("input", () =>
  $("record-name").setCustomValidity(""),
);
$("record-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const name = $("record-name").value.trim();
  if (!name) {
    $("record-name").setCustomValidity("请输入项目名称");
    $("record-name").reportValidity();
    return;
  }
  Object.assign(
    projects.find((item) => item.id === selectedId),
    {
      name,
      status: $("record-status").value,
      progress: Number($("record-progress").value),
      description: $("record-description").value.trim(),
    },
  );
  renderProjects();
  $("save-status").textContent = "已保存到本页示例";
});
$("record-form").addEventListener("reset", (event) => {
  event.preventDefault();
  $("record-name").setCustomValidity("");
  loadRecord();
  $("save-status").textContent = "已还原未保存修改";
});
renderProjects();
loadRecord();

const tabs = Array.from(document.querySelectorAll("[role=tab]"));
function selectTab(tab) {
  for (const item of tabs) {
    const selected = item === tab;
    item.setAttribute("aria-selected", String(selected));
    item.tabIndex = selected ? 0 : -1;
    $(item.getAttribute("aria-controls")).hidden = !selected;
  }
}
tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectTab(tab));
  tab.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = tabs[(index + 1) % tabs.length];
    if (event.key === "ArrowLeft")
      next = tabs[(index + tabs.length - 1) % tabs.length];
    if (event.key === "Home") next = tabs[0];
    if (event.key === "End") next = tabs[tabs.length - 1];
    if (next) {
      event.preventDefault();
      selectTab(next);
      next.focus();
    }
  });
});

$("run-query").addEventListener("click", () => {
  queryResult = projects
    .filter((item) => item.progress >= 70)
    .sort((a, b) => b.progress - a.progress)
    .map(({ name, progress }) => ({ name, progress }));
  const table = document.createElement("table");
  const head = document.createElement("thead");
  const headerRow = document.createElement("tr");
  ["name", "progress"].forEach((name) => {
    const th = document.createElement("th");
    th.scope = "col";
    th.textContent = name;
    headerRow.append(th);
  });
  head.append(headerRow);
  const body = document.createElement("tbody");
  queryResult.forEach((project) => {
    const row = document.createElement("tr");
    row.append(cell(project.name), cell(String(project.progress)));
    body.append(row);
  });
  table.append(head, body);
  const count = document.createElement("p");
  count.className = "result-count";
  count.textContent = `${queryResult.length} 条结果 · 当前页面示例数据`;
  $("query-results").replaceChildren(table, count);
  $("export-csv").disabled = false;
});

$("export-csv").addEventListener("click", () => {
  if (queryResult === null) return;
  // Spreadsheet apps can interpret formula-looking names even inside CSV quotes.
  const quote = (value) => {
    const text = String(value);
    const safe = /^[\s]*[=+@-]/.test(text) ? `'${text}` : text;
    return `"${safe.replaceAll('"', '""')}"`;
  };
  const csv =
    "\uFEFFname,progress\r\n" +
    queryResult.map((row) => `${quote(row.name)},${row.progress}`).join("\r\n");
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

let agentState = "pending";
function resolveOperation(approved) {
  if (agentState !== "pending") return;
  agentState = approved ? "executed" : "rejected";
  $("approve-operation").disabled = true;
  $("reject-operation").disabled = true;
  if (!approved) {
    $("agent-result").textContent = "已拒绝，未执行任何操作。";
    return;
  }
  const count = projects.filter((item) => item.progress >= 70).length;
  const message = document.createElement("p");
  message.textContent = `示例查询完成：${count} 条结果留在本页，尚未发送给模型。`;
  const share = document.createElement("button");
  share.className = "small-button blue";
  share.textContent = "发送结果并继续（模拟）";
  share.addEventListener("click", () => {
    if (agentState !== "executed") return;
    agentState = "shared";
    $("agent-result").textContent =
      `已完成第二次确认。示例中共有 ${count} 个项目达到目标进度；本演示没有向外发送数据。`;
  });
  $("agent-result").replaceChildren(message, share);
}
$("approve-operation").addEventListener("click", () => resolveOperation(true));
$("reject-operation").addEventListener("click", () => resolveOperation(false));
$("reset-agent").addEventListener("click", () => {
  agentState = "pending";
  $("agent-result").replaceChildren();
  $("approve-operation").disabled = false;
  $("reject-operation").disabled = false;
});

const dialog = $("screenshot-dialog");
$("open-screenshot").addEventListener("click", () => {
  dialog.showModal();
  document.body.style.overflow = "hidden";
});
$("close-screenshot").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (
      event.clientX < rect.left ||
      event.clientX > rect.right ||
      event.clientY < rect.top ||
      event.clientY > rect.bottom
    )
      dialog.close();
  }
});
dialog.addEventListener("close", () => {
  document.body.style.overflow = "";
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
if ("IntersectionObserver" in window && !reducedMotion.matches) {
  document.documentElement.classList.add("motion-ready");
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08 },
  );
  document
    .querySelectorAll(".reveal")
    .forEach((element) => observer.observe(element));
}
const windowPreview = $("open-screenshot");
windowPreview.addEventListener("pointermove", (event) => {
  if (reducedMotion.matches || event.pointerType !== "mouse") return;
  const rect = windowPreview.getBoundingClientRect();
  const x = (event.clientX - rect.left) / rect.width - 0.5;
  const y = (event.clientY - rect.top) / rect.height - 0.5;
  windowPreview.style.setProperty("--rx", `${-y * 2.4}deg`);
  windowPreview.style.setProperty("--ry", `${x * 2.4}deg`);
});
function resetTilt() {
  windowPreview.style.setProperty("--rx", "0deg");
  windowPreview.style.setProperty("--ry", "0deg");
}
windowPreview.addEventListener("pointerleave", resetTilt);
reducedMotion.addEventListener("change", resetTilt);
