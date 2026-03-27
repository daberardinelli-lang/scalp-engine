// WebRadar — JavaScript entry point
// Vanilla JS, nessun framework salvo indicazione esplicita

import "@hotwired/turbo-rails"

// Auto-hide flash messages dopo 4 secondi
document.addEventListener("turbo:load", () => {
  const flashes = document.querySelectorAll("[data-flash]")
  flashes.forEach(el => {
    setTimeout(() => {
      el.style.transition = "opacity 0.5s"
      el.style.opacity = "0"
      setTimeout(() => el.remove(), 500)
    }, 4000)
  })
})
