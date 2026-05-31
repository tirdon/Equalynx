/*
 * Equalynx - render layer.
 *
 * Turns engine tokens into individual MathJax-rendered SVG glyphs (one render per
 * token), lays them out, and renders them onto a Canvas 2D layout and backdrop.
 *
 * Exposes window.EqualynxRender = { loadMathJax, renderTokenSVG, tokenColor, layout,
 *                                   playWriteOn, initBackdrop }.
 */
(function () {
  "use strict";

  const MATHJAX_URL = "https://cdn.jsdelivr.net/npm/mathjax@4/tex-svg.js";
  const FONT_SIZE_PX = 70;

  let mathJaxPromise = null;



  function configureMathJax() {
    if (window.MathJax && window.MathJax.startup) {
      return;
    }
    window.MathJax = {
      startup: {
        typeset: false,
      },
      svg: {
        fontCache: "none",
      },
      options: {
        enableMenu: false,
      },
      output: {
        font: "mathjax-newcm",
      },
    };
  }

  function loadMathJax() {
    if (!mathJaxPromise) {
      configureMathJax();
      mathJaxPromise = new Promise((resolve, reject) => {
        if (window.MathJax && window.MathJax.tex2svgPromise) {
          window.MathJax.startup.promise.then(() => resolve(window.MathJax), reject);
          return;
        }

        const script = document.createElement("script");
        script.src = MATHJAX_URL;
        script.async = true;
        script.onload = () => {
          if (!window.MathJax || !window.MathJax.startup) {
            reject(new Error("MathJax loaded without the expected startup API"));
            return;
          }
          window.MathJax.startup.promise.then(() => resolve(window.MathJax), reject);
        };
        script.onerror = () => {
          reject(new Error("Could not load MathJax from " + MATHJAX_URL));
        };
        document.head.appendChild(script);
      });
    }
    return mathJaxPromise;
  }

  // Token colours on the dark backdrop.
  function tokenColor(kind) {
    switch (kind) {
      case "operator":
        return "ffd479"; // amber
      case "equals":
        return "7ad7c1"; // teal
      case "variable":
      case "constant":
        return "b8a4ff"; // violet
      default:
        return "e8ecff"; // near-white numbers
    }
  }

  // Render a single token's TeX math to a tightly-cropped MathJax SVG string.
  async function renderTokenSVG(texSource) {
    const MathJax = await loadMathJax();
    const node = await MathJax.tex2svgPromise(texSource, {
      display: false,
      em: FONT_SIZE_PX,
      ex: FONT_SIZE_PX / 2,
      containerWidth: 100000,
    });
    const svgElement = node.querySelector("svg");
    if (svgElement) {
      svgElement.setAttribute("aria-hidden", "true");
      
      if (!svgElement.getAttribute("xmlns")) {
        svgElement.setAttribute("xmlns", "http://www.w3.org/2000/svg");
      }
      
      const wStr = svgElement.getAttribute("width") || "";
      const hStr = svgElement.getAttribute("height") || "";
      
      const parseLength = (str) => {
        if (str.endsWith("ex")) return parseFloat(str) * (FONT_SIZE_PX / 2);
        if (str.endsWith("em")) return parseFloat(str) * FONT_SIZE_PX;
        return parseFloat(str) || FONT_SIZE_PX;
      };
      
      svgElement.setAttribute("width", Math.ceil(parseLength(wStr)));
      svgElement.setAttribute("height", Math.ceil(parseLength(hStr)));
      svgElement.style.color = "currentColor";
      
      return svgElement.outerHTML;
    }
    node.setAttribute("aria-hidden", "true");
    node.style.fontSize = FONT_SIZE_PX + "px";
    return node.outerHTML;
  }

  // --- Legacy Canvas 2D and DOM rendering ---
  
  function layout(board, elements) {
    const boardRect = board.getBoundingClientRect();
    const gap = 20;
    const glueGap = 3;

    const sizes = elements.map((el) => el.getBoundingClientRect());
    const leadGap = (i) =>
      i === 0 ? 0 : elements[i].dataset.glue === "true" ? glueGap : gap;

    let totalWidth = 0;
    sizes.forEach((r, i) => {
      totalWidth += r.width + leadGap(i);
    });

    let x = (boardRect.width - totalWidth) / 2;
    const midY = boardRect.height / 2;

    elements.forEach((el, i) => {
      const r = sizes[i];
      x += leadGap(i);
      const top = midY - r.height / 2;
      el.style.left = x + "px";
      el.style.top = top + "px";
      el.dataset.homeLeft = String(x);
      el.dataset.homeTop = String(top);
      x += r.width;
    });
  }

  function playWriteOn(elements) {
    elements.forEach((el, i) => {
      el.style.animationDelay = i * 85 + "ms";
      el.classList.add("in");
    });
  }

  function initBackdrop(canvas) {
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }
    let dpr = 1;

    function resize() {
      dpr = window.devicePixelRatio || 1;
      canvas.width = Math.floor(window.innerWidth * dpr);
      canvas.height = Math.floor(window.innerHeight * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function draw(t) {
      const w = window.innerWidth;
      const h = window.innerHeight;

      const gradient = ctx.createLinearGradient(0, 0, 0, h);
      gradient.addColorStop(0, "#101430");
      gradient.addColorStop(1, "#070812");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, w, h);

      const spacing = 40;
      const offset = (t * 0.012) % spacing;
      ctx.fillStyle = "rgba(120,140,255,0.10)";
      for (let y = -spacing + offset; y < h + spacing; y += spacing) {
        for (let x = -spacing + offset; x < w + spacing; x += spacing) {
          ctx.beginPath();
          ctx.arc(x, y, 1.4, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      requestAnimationFrame(draw);
    }

    resize();
    window.addEventListener("resize", resize);
    requestAnimationFrame(draw);
  }



  window.EqualynxRender = {
    loadMathJax: loadMathJax,
    renderTokenSVG: renderTokenSVG,
    tokenColor: tokenColor,
    layout: layout,
    playWriteOn: playWriteOn,
    initBackdrop: initBackdrop,
  };
})();
