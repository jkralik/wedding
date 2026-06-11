async function loadMarkdownContent() {
  const container = document.getElementById("markdown-content");

  try {
    const response = await fetch("content.md", { cache: "no-cache" });
    if (!response.ok) {
      throw new Error(`Failed to load markdown: ${response.status}`);
    }

    const markdown = await response.text();
    container.innerHTML = marked.parse(markdown);
  } catch (error) {
    console.error(error);
    container.innerHTML = `
      <h2>Obsah sa nepodarilo načítať</h2>
      <p>Skontrolujte, či súbor <strong>content.md</strong> existuje.</p>
    `;
  }
}

loadMarkdownContent();
