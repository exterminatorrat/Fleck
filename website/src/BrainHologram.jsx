import { useEffect, useRef } from "react";
import { createBrainModel } from "./brainModel";

const GRAPHITE = [23, 25, 31];
const VIOLET = [116, 87, 246];

function rgba([red, green, blue], alpha) {
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}

export default function BrainHologram() {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const context = canvas.getContext("2d");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const pointer = { active: false, x: 0, y: 0 };
    let model;
    let frame;
    let width = 0;
    let height = 0;

    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      width = Math.max(1, bounds.width);
      height = Math.max(1, bounds.height);
      const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      const count = window.innerWidth < 600 ? 340 : width < 1100 ? 440 : 560;
      model = createBrainModel(width, height, count);
    };

    const positionNodes = (time) => {
      const radius = Math.min(width, height) * 0.14;
      model.nodes.forEach((node, index) => {
        const drift = reducedMotion.matches ? 0 : Math.sin(time * 0.00032 + node.phase) * 1.35;
        let x = node.x + drift * Math.cos(node.phase);
        let y = node.y + drift * Math.sin(node.phase);

        if (!reducedMotion.matches && pointer.active) {
          const dx = x - pointer.x;
          const dy = y - pointer.y;
          const distance = Math.hypot(dx, dy) || 1;
          if (distance < radius) {
            const force = ((radius - distance) / radius) ** 2 * 20;
            x += (dx / distance) * force;
            y += (dy / distance) * force;
          }
        }

        model.positions[index * 2] = x;
        model.positions[index * 2 + 1] = y;
      });
    };

    const draw = (time = 0) => {
      if (!model) resize();
      context.clearRect(0, 0, width, height);
      positionNodes(time);

      model.edges.forEach(([from, to]) => {
        const signal = model.signals.has(`${from}:${to}`);
        context.beginPath();
        context.moveTo(model.positions[from * 2], model.positions[from * 2 + 1]);
        context.lineTo(model.positions[to * 2], model.positions[to * 2 + 1]);
        context.strokeStyle = signal ? rgba(VIOLET, 0.28) : rgba(GRAPHITE, 0.13);
        context.lineWidth = signal ? 0.95 : 0.58;
        context.stroke();
      });

      model.nodes.forEach((node, index) => {
        const x = model.positions[index * 2];
        const y = model.positions[index * 2 + 1];
        if (node.violet) {
          context.beginPath();
          context.arc(x, y, node.size * 4.4, 0, Math.PI * 2);
          context.fillStyle = rgba(VIOLET, 0.07);
          context.fill();
        }
        context.beginPath();
        context.arc(x, y, node.size, 0, Math.PI * 2);
        context.fillStyle = node.violet ? rgba(VIOLET, 0.72) : rgba(GRAPHITE, 0.5);
        context.fill();
      });

      if (!reducedMotion.matches) frame = window.requestAnimationFrame(draw);
    };

    const updatePointer = (event) => {
      const bounds = canvas.getBoundingClientRect();
      pointer.x = event.clientX - bounds.left;
      pointer.y = event.clientY - bounds.top;
      pointer.active =
        event.pointerType !== "touch" &&
        pointer.x >= 0 &&
        pointer.x <= bounds.width &&
        pointer.y >= 0 &&
        pointer.y <= bounds.height;
    };

    const restart = () => {
      window.cancelAnimationFrame(frame);
      draw(0);
    };
    const observer = new ResizeObserver(() => {
      resize();
      if (reducedMotion.matches) draw(0);
    });

    observer.observe(canvas);
    window.addEventListener("pointermove", updatePointer, { passive: true });
    reducedMotion.addEventListener("change", restart);
    resize();
    draw(0);

    return () => {
      observer.disconnect();
      window.cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", updatePointer);
      reducedMotion.removeEventListener("change", restart);
    };
  }, []);

  return (
    <div className="brain-hologram" aria-hidden="true">
      <div className="brain-hologram-visual">
        <canvas ref={canvasRef} className="brain-network" />
      </div>
    </div>
  );
}
