import {Socket} from "../deps/phoenix/priv/static/phoenix.mjs";
import "../deps/phoenix_html/priv/static/phoenix_html.js";
import {LiveSocket} from "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js";
const geometry = block => Object.fromEntries(["x", "y", "w", "h"].map(k => [k, Number(block.dataset[k])]));
const paint = (block, value) => {
  for (const [key, property] of Object.entries({x:"left",y:"top",w:"width",h:"height"})) block.style[property] = `${value[key]*40}px`;
};
const Grid = {
  mounted() {
    this.down = e => {
      const block = e.target.closest("[data-block]");
      if (!block || e.button !== 0 || this.drag || this.pending) return;
      this.suppressClick = false;
      this.drag = {block, pointer: e.pointerId, x: e.clientX, y: e.clientY, original: geometry(block), resize: e.target.closest(".resize"), moved: false};
      block.setPointerCapture(e.pointerId);
      this.gesture = new AbortController();
      const options = {signal: this.gesture.signal};
      window.addEventListener("pointermove", event => this.move(event), options);
      window.addEventListener("pointerup", event => this.finish(event), options);
      window.addEventListener("pointercancel", () => this.cancel(), options);
      window.addEventListener("blur", () => this.cancel(), options);
      window.addEventListener("keydown", event => {if (event.key === "Escape") this.cancel();}, options);
    };
    this.click = e => {
      if (this.suppressClick) {e.preventDefault();e.stopImmediatePropagation();this.suppressClick = false;}
    };
    this.el.addEventListener("pointerdown", this.down);
    this.el.addEventListener("click", this.click, true);
  },
  move(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.pointer) return;
    d.dx = e.clientX-d.x; d.dy = e.clientY-d.y;
    d.moved ||= Math.abs(d.dx)+Math.abs(d.dy) > 3;
    if (!d.moved) return;
    e.preventDefault();
    if (!this.frame) this.frame = requestAnimationFrame(() => {this.frame = null;this.paintDrag();});
  },
  paintDrag() {
    const d = this.drag;
    if (!d?.moved) return;
    d.block.classList.add("dragging");
    if (d.resize) {
      d.block.style.width = `${Math.max(80,d.original.w*40+d.dx)}px`;
      d.block.style.height = `${Math.max(40,d.original.h*40+d.dy)}px`;
    } else {
      d.block.style.transform = `translate(${d.dx}px,${d.dy}px)`;
    }
  },
  finish(e) {
    const d = this.drag;
    if (!d || e.pointerId !== d.pointer) return;
    const dx = Math.round((e.clientX-d.x)/40), dy = Math.round((e.clientY-d.y)/40);
    this.cleanup();
    if (!d.moved) return;
    this.suppressClick = true;
    // Keep the snapped position visible while the server validates it.
    const value = {...d.original, ...(d.resize ? {w:d.original.w+dx,h:d.original.h+dy} : {x:d.original.x+dx,y:d.original.y+dy})};
    this.pending = {block:d.block, value};
    paint(d.block, value);
    this.pushEvent("geometry", {id:d.block.dataset.block, ...value}, reply => {
      this.pending = null;
      if (reply.geometry) paint(d.block, reply.geometry);
      else paint(d.block, geometry(d.block));
    });
  },
  cleanup() {
    const d = this.drag;
    this.gesture?.abort();
    cancelAnimationFrame(this.frame);this.frame = null;
    if (d) {
      d.block.style.transform = "";
      d.block.classList.remove("dragging");
      if (d.block.hasPointerCapture(d.pointer)) d.block.releasePointerCapture(d.pointer);
      paint(d.block, d.original);
    }
    this.drag = null;
  },
  cancel() {this.suppressClick = !!this.drag?.moved;this.cleanup();},
  updated() {
    this.paintDrag();
    if (this.pending) paint(this.pending.block, this.pending.value);
  },
  disconnected() {
    this.cancel();
    if (this.pending) paint(this.pending.block, geometry(this.pending.block));
    this.pending = null;
  },
  destroyed() {
    this.disconnected();
    this.el.removeEventListener("pointerdown", this.down);
    this.el.removeEventListener("click", this.click, true);
  }
};
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: document.querySelector("meta[name=csrf-token]").content}, hooks: {Grid}});
liveSocket.connect();
window.liveSocket = liveSocket;
