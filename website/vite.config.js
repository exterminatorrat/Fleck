import { defineConfig } from "vite";

export default defineConfig({
  appType: "spa",
  build: {
    rolldownOptions: {
      output: {
        comments: { legal: true },
      },
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
  },
});
