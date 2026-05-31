/*
 * Equalynx - game/orchestration layer.
 *
 * Boots the backdrop, waits for the engine + MathJax, then renders the current
 * equation as draggable MathJax-SVG tokens using the DOM.
 * Dropping one number tile across the `=` onto the other side triggers a combine
 * move in the Swift engine.
 *
 * Core rule: dragging a tile across the equals applies its inverse to both sides.
 * Solving 2x + 3 = 5:
 *   - drag the addend 3 onto 5  → additive inverse  → 2x = 2
 *   - drag the multiplicand 2 onto 2 → multiplicative inverse → x = 1   (goal)
 * The returned equation is re-rendered with a fade-out / write-on transition.
 */
(function () {
  "use strict";

  const START_EQUATION = "2x + 3 = 5";
  const STEP_TWO = "2x = 2";
  const GOAL = "x = 1";

  let board = null;
  let currentEquation = START_EQUATION;
  let tokenEls = [];
  let busy = false; // guards against drops during a re-render
  let renderId = 0; // tracks the latest rendering sequence to avoid overlapping races

  let draggedToken = null;
  let dragOffsetX = 0;
  let dragOffsetY = 0;

  async function main() {
    board = document.getElementById("board");
    const canvas = document.getElementById("fx");
    
    // Await Canvas 2D backdrop initialization
    await EqualynxRender.initBackdrop(canvas);

    await Promise.all([EqualynxRender.loadMathJax(), window.Equalynx.ready]);

    await renderEquation(currentEquation);
  }



  // Render an equation string into draggable token elements (DOM)
  async function renderEquation(equation) {
    const myRenderId = ++renderId;
    const tokens = window.Equalynx.parse(equation);
    currentEquation = equation;

    const localTokenEls = [];

    for (const token of tokens) {
      const svg = await EqualynxRender.renderTokenSVG(token.tex);
      if (myRenderId !== renderId) {
        return;
      }
      const el = document.createElement("div");
      el.className = "token";
      el.dataset.id = String(token.id);
      el.dataset.kind = token.kind;
      el.dataset.value = token.value;
      el.dataset.glue = token.glue ? "true" : "false";
      el.style.color = "#" + EqualynxRender.tokenColor(token.kind);
      el.innerHTML = svg;
      localTokenEls.push(el);
    }

    if (myRenderId !== renderId) {
      return;
    }

    board.innerHTML = "";
    tokenEls = localTokenEls;

    for (const el of tokenEls) {
      board.appendChild(el);
    }

    EqualynxRender.layout(board, tokenEls);
    EqualynxRender.playWriteOn(tokenEls);
    tokenEls.forEach(makeDraggable);
    renderHud();
  }

  // The persistent goal label, a step-aware hint, and the win banner. Rebuilt each
  // render because renderEquation clears the board HUD wrapper.
  function renderHud() {
    const existingHudElements = board.querySelectorAll('.goal, .win, .hint');
    existingHudElements.forEach(el => el.remove());
    
    const goal = document.createElement("div");
    goal.className = "goal";
    goal.innerHTML = 'Goal&nbsp;&nbsp;<span class="goal-eq">x = 1</span>';
    board.appendChild(goal);

    if (currentEquation === GOAL) {
      const win = document.createElement("div");
      win.className = "win";
      win.textContent = "Solved!  x = 1";
      board.appendChild(win);
      return;
    }

    const hint = document.createElement("div");
    hint.className = "hint";
    hint.textContent = hintFor(currentEquation);
    board.appendChild(hint);
  }

  function hintFor(equation) {
    if (equation === START_EQUATION) {
      return "Drag the 3 across onto the 5";
    }
    if (equation === STEP_TWO) {
      return "Now drag the 2 across onto the 2";
    }
    return "Drag a tile across the = to move it by its inverse";
  }

  function makeDraggable(el) {
    el.addEventListener("pointerdown", (event) => {
      if (busy) {
        return;
      }
      event.preventDefault();
      el.setPointerCapture(event.pointerId);
      el.classList.add("dragging");

      const startX = event.clientX;
      const startY = event.clientY;
      const baseLeft = parseFloat(el.style.left) || 0;
      const baseTop = parseFloat(el.style.top) || 0;

      const onMove = (moveEvent) => {
        el.style.left = baseLeft + (moveEvent.clientX - startX) + "px";
        el.style.top = baseTop + (moveEvent.clientY - startY) + "px";
      };
      const onUp = () => {
        el.classList.remove("dragging");
        try {
          el.releasePointerCapture(event.pointerId);
        } catch (e) {
          /* pointer already released */
        }
        el.removeEventListener("pointermove", onMove);
        el.removeEventListener("pointerup", onUp);
        el.removeEventListener("pointercancel", onUp);
        handleDrop(el);
      };

      el.addEventListener("pointermove", onMove);
      el.addEventListener("pointerup", onUp);
      el.addEventListener("pointercancel", onUp);
    });
  }

  // On drop: if a number tile was dropped onto another number tile, try a combine.
  function handleDrop(dragged) {
    if (busy) {
      snapBack(dragged);
      return;
    }

    const kind = dragged.dataset.kind;
    if (kind !== "number") {
      snapBack(dragged);
      return;
    }

    const target = numberTokenUnder(dragged);
    if (!target) {
      snapBack(dragged);
      return;
    }

    const draggedId = parseInt(dragged.dataset.id, 10);
    const targetId = parseInt(target.dataset.id, 10);
    const result = window.Equalynx.combine(currentEquation, draggedId, targetId);

    if (!result.ok) {
      flashReject(target);
      snapBack(dragged);
      return;
    }
    resolveInto(result.text);
  }

  // Find a number token (not the dragged one) whose box contains the dragged center.
  function numberTokenUnder(dragged) {
    const r = dragged.getBoundingClientRect();
    const cx = r.left + r.width / 2;
    const cy = r.top + r.height / 2;
      for (const el of tokenEls) {
        if (el === dragged || el.dataset.kind !== "number") {
          continue;
        }
        const b = el.getBoundingClientRect();
        if (cx >= b.left && cx <= b.right && cy >= b.top && cy <= b.bottom) {
          return el;
        }
      }
    return null;
  }

  // Fade the current tiles out, then render the resulting equation.
  function resolveInto(equation) {
    busy = true;

    tokenEls.forEach((el) => {
        el.style.transition = "opacity 200ms ease, transform 200ms ease";
        el.style.opacity = "0";
        el.style.transform = "scale(0.8)";
      });
      setTimeout(() => {
        renderEquation(equation)
          .catch((error) => showError(error))
          .finally(() => {
            busy = false;
          });
      }, 210);
  }

  function snapBack(dragged) {
    const homeLeft = dragged.dataset.homeLeft;
    const homeTop = dragged.dataset.homeTop;
    if (homeLeft === undefined || homeTop === undefined) {
      return;
    }
      dragged.style.transition = "left 240ms cubic-bezier(.2,.8,.2,1), top 240ms cubic-bezier(.2,.8,.2,1)";
      dragged.style.left = homeLeft + "px";
      dragged.style.top = homeTop + "px";
      setTimeout(() => {
        dragged.style.transition = "";
    }, 260);
  }

  function flashReject(dragged) {
    dragged.animate(
        [
          { transform: "translateX(0)" },
          { transform: "translateX(-5px)" },
          { transform: "translateX(5px)" },
          { transform: "translateX(0)" },
        ],
        { duration: 220, easing: "ease-in-out" }
    );
  }

  function showError(error) {
    console.error("[Equalynx]", error);
    const box = document.createElement("div");
    box.className = "error";
    box.textContent =
      "Could not start Equalynx: " + (error && error.message ? error.message : error);
    board.appendChild(box);
  }

  // `defer` guarantees the DOM is parsed before this runs.
  main().catch((error) => {
    board = board || document.getElementById("board");
    showError(error);
  });
})();
