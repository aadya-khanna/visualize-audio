const CLIENT_ID = import.meta.env.VITE_SPOTIFY_CLIENT_ID
const REDIRECT_URI = window.location.origin + window.location.pathname
const SCOPES = ['user-read-currently-playing', 'user-read-playback-state']

const STORAGE_KEY = 'spotify_pkce'

function base64url(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

async function sha256(plain) {
  const data = new TextEncoder().encode(plain)
  return crypto.subtle.digest('SHA-256', data)
}

function randomString(length = 64) {
  const arr = new Uint8Array(length)
  crypto.getRandomValues(arr)
  return base64url(arr.buffer)
}

export async function login() {
  const verifier = randomString()
  const challenge = base64url(await sha256(verifier))
  localStorage.setItem('spotify_verifier', verifier)

  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    response_type: 'code',
    redirect_uri: REDIRECT_URI,
    scope: SCOPES.join(' '),
    code_challenge_method: 'S256',
    code_challenge: challenge,
  })

  window.location.href = `https://accounts.spotify.com/authorize?${params}`
}

async function exchangeCodeForToken(code) {
  const verifier = localStorage.getItem('spotify_verifier')
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    grant_type: 'authorization_code',
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  })

  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) throw new Error('Spotify token exchange failed')
  const data = await res.json()
  saveTokens(data)
  return data
}

async function refreshToken() {
  const stored = getStoredTokens()
  if (!stored?.refresh_token) return null

  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    grant_type: 'refresh_token',
    refresh_token: stored.refresh_token,
  })

  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!res.ok) return null
  const data = await res.json()
  saveTokens({ ...data, refresh_token: data.refresh_token || stored.refresh_token })
  return data
}

function saveTokens(data) {
  const expiresAt = Date.now() + data.expires_in * 1000
  localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...data, expires_at: expiresAt }))
}

function getStoredTokens() {
  const raw = localStorage.getItem(STORAGE_KEY)
  return raw ? JSON.parse(raw) : null
}

// Call once on app load. Handles the OAuth redirect (?code=...) if present,
// otherwise returns a valid access token from storage, refreshing if expired.
export async function getAccessToken() {
  const url = new URL(window.location.href)
  const code = url.searchParams.get('code')
  if (code) {
    url.searchParams.delete('code')
    window.history.replaceState({}, '', url.toString())
    const data = await exchangeCodeForToken(code)
    return data.access_token
  }

  const stored = getStoredTokens()
  if (!stored) return null
  if (Date.now() < stored.expires_at - 5000) return stored.access_token

  const refreshed = await refreshToken()
  return refreshed?.access_token ?? null
}

export function logout() {
  localStorage.removeItem(STORAGE_KEY)
}

export async function getCurrentlyPlaying(accessToken) {
  const res = await fetch('https://api.spotify.com/v1/me/player/currently-playing', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
  if (res.status === 204) return null // nothing playing
  if (!res.ok) throw new Error(`Spotify API error ${res.status}`)
  const data = await res.json()
  return {
    name: data.item?.name,
    artists: data.item?.artists?.map((a) => a.name).join(', '),
    albumArt: data.item?.album?.images?.[0]?.url,
    progressMs: data.progress_ms,
    durationMs: data.item?.duration_ms,
    isPlaying: data.is_playing,
  }
}
