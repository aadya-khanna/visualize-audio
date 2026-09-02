import { SpotifyIcon, DeezerIcon, SoundCloudIcon, AppleMusicIcon } from './icons'

// Only Spotify authenticates client-side (Authorization Code + PKCE, no
// secret). Deezer and SoundCloud both require a client_secret in their token
// exchange — not safe to hold in a browser-only app — so they're shown as
// logos with no live connection until this app has a backend to hold that
// secret. Apple Music needs a paid developer account + MusicKit besides.
const SERVICES = [
  { key: 'spotify', label: 'Spotify', Icon: SpotifyIcon, enabled: true },
  { key: 'deezer', label: 'Deezer', Icon: DeezerIcon, enabled: false },
  { key: 'soundcloud', label: 'SoundCloud', Icon: SoundCloudIcon, enabled: false },
  { key: 'applemusic', label: 'Apple Music', Icon: AppleMusicIcon, enabled: false },
]

export default function MusicConnect({ connected, connecting, onConnect, onDisconnect }) {
  return (
    <div className="music-connect">
      {SERVICES.map(({ key, label, Icon, enabled }) => {
        const isSpotify = key === 'spotify'
        const active = isSpotify && connected
        const title = !enabled
          ? `${label} — coming soon`
          : active
            ? `Disconnect ${label}`
            : connecting
              ? `Connecting to ${label}…`
              : `Connect ${label}`

        return (
          <button
            key={key}
            type="button"
            className={`music-icon-button${active ? ' connected' : ''}`}
            disabled={!enabled || (isSpotify && connecting)}
            title={title}
            aria-label={title}
            onClick={isSpotify ? (active ? onDisconnect : onConnect) : undefined}
          >
            <Icon />
          </button>
        )
      })}
    </div>
  )
}
