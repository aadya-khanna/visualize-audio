import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // Spotify's redirect URI matching requires the literal loopback IP
  // (127.0.0.1), not "localhost" — bind explicitly so the OAuth redirect
  // actually reaches this server instead of hitting an IPv6-only listener.
  server: {
    host: '127.0.0.1',
    port: 5173,
  },
})
