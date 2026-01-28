// Include phoenix_html to handle method=PUT/DELETE in forms and buttons
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// LiveView Hooks
let Hooks = {}

// Infinite scroll hook for loading more content
Hooks.InfiniteScroll = {
  mounted() {
    this.observer = new IntersectionObserver(entries => {
      const entry = entries[0]
      if (entry.isIntersecting) {
        this.pushEvent("load-more", {})
      }
    })
    this.observer.observe(this.el)
  },
  destroyed() {
    this.observer.disconnect()
  }
}

// Local time display hook - converts UTC timestamps to local time
Hooks.LocalTime = {
  mounted() {
    this.updated()
  },
  updated() {
    const dt = new Date(this.el.textContent.trim())
    if (!isNaN(dt)) {
      this.el.textContent = dt.toLocaleString()
      this.el.classList.remove("invisible")
    }
  }
}

// Relative time display (e.g., "2 hours ago")
Hooks.RelativeTime = {
  mounted() {
    this.updated()
    // Update every minute
    this.timer = setInterval(() => this.updated(), 60000)
  },
  updated() {
    const dt = new Date(this.el.dataset.datetime)
    if (!isNaN(dt)) {
      this.el.textContent = this.timeAgo(dt)
    }
  },
  destroyed() {
    clearInterval(this.timer)
  },
  timeAgo(date) {
    const seconds = Math.floor((new Date() - date) / 1000)
    const intervals = {
      year: 31536000,
      month: 2592000,
      week: 604800,
      day: 86400,
      hour: 3600,
      minute: 60
    }
    for (const [unit, secondsInUnit] of Object.entries(intervals)) {
      const interval = Math.floor(seconds / secondsInUnit)
      if (interval >= 1) {
        return interval === 1 ? `1 ${unit} ago` : `${interval} ${unit}s ago`
      }
    }
    return "just now"
  }
}

// Focus input on mount
Hooks.Focus = {
  mounted() {
    this.el.focus()
  }
}

// Copy to clipboard
Hooks.Copy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copy
      navigator.clipboard.writeText(text).then(() => {
        // Show success feedback
        const original = this.el.innerHTML
        this.el.innerHTML = '<span class="text-green-600">Copied!</span>'
        setTimeout(() => {
          this.el.innerHTML = original
        }, 2000)
      })
    })
  }
}

// Google Places Autocomplete hook for location inputs
Hooks.PlacesAutocomplete = {
  mounted() {
    this.initAutocomplete()
  },
  initAutocomplete() {
    if (typeof google === "undefined" || !google.maps || !google.maps.places) {
      setTimeout(() => this.initAutocomplete(), 200)
      return
    }

    const input = this.el.querySelector("input[data-places-input]")
    if (!input) return

    this.autocomplete = new google.maps.places.Autocomplete(input, {
      types: ["establishment", "geocode"]
    })

    this.autocomplete.addListener("place_changed", () => {
      const place = this.autocomplete.getPlace()
      if (!place.geometry) return

      this.pushEventTo(this.el, "place-selected", {
        address: place.formatted_address || place.name,
        place_id: place.place_id,
        lat: place.geometry.location.lat(),
        lng: place.geometry.location.lng()
      })
    })
  },
  destroyed() {
    if (this.autocomplete) {
      google.maps.event.clearInstanceListeners(this.autocomplete)
    }
  }
}

// Google Map display hook
Hooks.GoogleMap = {
  mounted() {
    this.initMap()
  },
  updated() {
    this.initMap()
  },
  initMap() {
    if (typeof google === "undefined" || !google.maps) {
      setTimeout(() => this.initMap(), 200)
      return
    }

    const lat = parseFloat(this.el.dataset.lat)
    const lng = parseFloat(this.el.dataset.lng)
    if (isNaN(lat) || isNaN(lng)) return

    const position = { lat, lng }

    if (!this.map) {
      this.map = new google.maps.Map(this.el, {
        center: position,
        zoom: 15,
        disableDefaultUI: true,
        zoomControl: true,
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false
      })
      this.marker = new google.maps.Marker({ position, map: this.map })
    } else {
      this.map.setCenter(position)
      this.marker.setPosition(position)
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#5046e5"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
