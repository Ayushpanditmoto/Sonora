"use client";
import { useState } from "react";
import { Search as SearchIcon } from "lucide-react";
import {
  useAlbums,
  useArtists,
  usePlaylists,
  useSongs,
} from "@/hooks/use-music";
import { SongList } from "@/components/song-list";
import { Cards } from "@/components/cards";
export default function SearchPage() {
  const [query, setQuery] = useState("");
  const songs = useSongs(query);
  const albums = useAlbums(query);
  const artists = useArtists(query);
  const playlists = usePlaylists(query);
  return (
    <>
      <h1 className="text-3xl font-black">Search</h1>
      <div className="mt-6 flex max-w-2xl items-center gap-3 rounded-full bg-white/10 px-5 py-3 focus-within:ring-2 focus-within:ring-brand">
        <SearchIcon className="text-zinc-400" />
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="What do you want to listen to?"
          className="w-full bg-transparent outline-none placeholder:text-zinc-400"
        />
      </div>
      {!query && (
        <p className="mt-10 text-zinc-400">
          Search for songs, albums, artists or playlists.
        </p>
      )}
      {query && (
        <div className="mt-10 space-y-11">
          {songs.isLoading ? (
            <p className="animate-pulse text-zinc-400">Searching your music…</p>
          ) : songs.isError ? (
            <p className="text-red-300">
              Search failed. Check your connection and try again.
            </p>
          ) : (
            <section>
              <h2 className="mb-4 text-2xl font-bold">Songs</h2>
              <SongList songs={songs.data?.results || []} />
            </section>
          )}
          <section>
            <h2 className="mb-4 text-2xl font-bold">Albums</h2>
            <Cards items={albums.data?.results || []} type="album" />
          </section>
          <section>
            <h2 className="mb-4 text-2xl font-bold">Artists</h2>
            <Cards items={artists.data?.results || []} type="artist" />
          </section>
          <section>
            <h2 className="mb-4 text-2xl font-bold">Playlists</h2>
            <Cards items={playlists.data?.results || []} type="playlist" />
          </section>
        </div>
      )}
    </>
  );
}
