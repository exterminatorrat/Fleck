import { useEffect, useRef } from "react";
import { createBrainModel } from "./brainModel";

const GRAPHITE = [23, 25, 31];
const VIOLET = [103, 73, 255];

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
      const ratio = Math.min(window.devicePixelRatio || 1, 2);

      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
      context.setTransform(ratio, 0, 0, ratio, 0, 0);

      const count = width < 600 ? 220 : width < 900 ? 330 : 470;
      model = createBrainModel(width, height, count);
    };

    const positionNodes = (time) => {
      const radius = Math.min(width, height) * 0.17;

      model.nodes.forEach((node, index) => {
        const ambient = reducedMotion.matches
          ? 0
          : Math.sin(time * 0.00035 + node.phase) * 2.2;
        let x = node.x + ambient * Math.cos(node.phase);
        let y = node.y + ambient * Math.sin(node.phase);

        if (!reducedMotion.matches && pointer.active) {
          const dx = x - pointer.x;
          const dy = y - pointer.y;
          const distance = Math.hypot(dx, dy) || 1;

          if (distance < radius) {
            const force = ((radius - distance) / radius) ** 2 * 34;
            x += (dx / distance) * force;
            y += (dy / distance) * force;
          }
        }

        model.positions[index * 2] = x;
        model.positions[index * 2 + 1] = y;
      });
    };

    const drawContours = () => {
      const mobile = width < 600;
      const centerY = height * 0.52;
      const radiusX = mobile
        ? width * 0.48
        : Math.min(width * 0.275, height * 0.43);
      const radiusY = height * (mobile ? 0.39 : 0.43);

      [-1, 1].forEach((side) => {
        const centerX = width * (side === -1 ? (mobile ? 0.19 : 0.34) : mobile ? 0.81 : 0.66);

        for (let line = -4; line <= 4; line += 1) {
          const y = centerY + line * radiusY * 0.13;
          const outerX = centerX + side * radiusX * 0.9;
          const innerX = centerX - side * radiusX * 0.42;

          context.beginPath();
          context.moveTo(outerX, y);
          context.bezierCurveTo(
            centerX + side * radiusX * 0.48,
            y - radiusY * 0.2,
            centerX - side * radiusX * 0.08,
            y + radiusY * 0.2,
            innerX,
            y,
          );
          context.strokeStyle = rgba(VIOLET, 0.055);
          context.lineWidth = 0.8;
          context.stroke();
        }
      });
    };

    const draw = (time = 0) => {
      if (!model) resize();

      context.clearRect(0, 0, width, height);
      positionNodes(time);
      drawContours();

      model.edges.forEach(([from, to]) => {
        const key = `${from}:${to}`;
        const signal = model.signals.has(key);
        context.beginPath();
        context.moveTo(model.positions[from * 2], model.positions[from * 2 + 1]);
        context.lineTo(model.positions[to * 2], model.positions[to * 2 + 1]);
        context.strokeStyle = signal
          ? rgba(VIOLET, 0.26)
          : rgba(GRAPHITE, 0.105);
        context.lineWidth = signal ? 1.05 : 0.68;
        context.stroke();
      });

      model.nodes.forEach((node, index) => {
        if (node.violet) {
          context.beginPath();
          context.arc(
            model.positions[index * 2],
            model.positions[index * 2 + 1],
            node.size * 4.5,
            0,
            Math.PI * 2,
          );
          context.fillStyle = rgba(VIOLET, 0.055);
          context.fill();
        }

        context.beginPath();
        context.arc(
          model.positions[index * 2],
          model.positions[index * 2 + 1],
          node.size,
          0,
          Math.PI * 2,
        );
        context.fillStyle = node.violet
          ? rgba(VIOLET, 0.82)
          : rgba(GRAPHITE, 0.68);
        context.fill();
      });

      if (pointer.active && !reducedMotion.matches) {
        for (let ring = 0; ring < 3; ring += 1) {
          context.beginPath();
          context.arc(pointer.x, pointer.y, 23 + ring * 17, -0.85, 0.85);
          context.strokeStyle = rgba(VIOLET, 0.16 - ring * 0.035);
          context.lineWidth = 1;
          context.stroke();
        }
      }

      if (!reducedMotion.matches) frame = window.requestAnimationFrame(draw);
    };

    const updatePointer = (event) => {
      const bounds = canvas.getBoundingClientRect();
      pointer.x = event.clientX - bounds.left;
      pointer.y = event.clientY - bounds.top;
      pointer.active =
        pointer.x >= 0 &&
        pointer.x <= bounds.width &&
        pointer.y >= 0 &&
        pointer.y <= bounds.height;
    };

    const releaseTouch = (event) => {
      if (event.pointerType === "touch") pointer.active = false;
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
    window.addEventListener("pointerdown", updatePointer, { passive: true });
    window.addEventListener("pointerup", releaseTouch, { passive: true });
    reducedMotion.addEventListener("change", restart);
    resize();
    draw(0);

    return () => {
      observer.disconnect();
      window.cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", updatePointer);
      window.removeEventListener("pointerdown", updatePointer);
      window.removeEventListener("pointerup", releaseTouch);
      reducedMotion.removeEventListener("change", restart);
    };
  }, []);

  return <canvas ref={canvasRef} className="brain-hologram" aria-hidden="true" />;
}
