const root = document.documentElement;
const storedTheme = localStorage.getItem("mactools-theme");
const storedLang = localStorage.getItem("mactools-lang");

if (storedTheme === "dark" || storedTheme === "light") {
  root.dataset.theme = storedTheme;
} else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  root.dataset.theme = "dark";
}

if (storedLang === "zh" || storedLang === "en") {
  root.dataset.lang = storedLang;
  root.lang = storedLang === "zh" ? "zh-CN" : "en";
}

document.querySelectorAll<HTMLElement>("[data-copy]").forEach((button) => {
  const initialText = button.textContent ?? "复制";
  button.addEventListener("click", async () => {
    const value = button.dataset.copy;
    if (!value) return;

    try {
      await navigator.clipboard.writeText(value);
      button.textContent = root.dataset.lang === "en" ? "Copied" : "已复制";
      window.setTimeout(() => {
        button.textContent = initialText;
      }, 1600);
    } catch {
      button.textContent = value;
    }
  });
});

document.querySelector<HTMLElement>("[data-theme-toggle]")?.addEventListener("click", () => {
  const next = root.dataset.theme === "dark" ? "light" : "dark";
  root.dataset.theme = next;
  localStorage.setItem("mactools-theme", next);
});

document.querySelector<HTMLElement>("[data-language-toggle]")?.addEventListener("click", () => {
  const next = root.dataset.lang === "en" ? "zh" : "en";
  root.dataset.lang = next;
  root.lang = next === "zh" ? "zh-CN" : "en";
  localStorage.setItem("mactools-lang", next);
});
