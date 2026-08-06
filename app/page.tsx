"use client";
import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import {
  useSongs,
  useAlbums,
  useArtists,
  usePlaylists,
} from "@/hooks/use-music";
import { SongList } from "@/components/song-list";
import { Cards } from "@/components/cards";
import { CardsShimmer } from "@/components/loading-shimmer";
import { RecentlyPlayed } from "@/components/recently-played";

export default function Home() {
  const songs = useSongs("Hindi hits");
  const albums = useAlbums("Hindi");
  const artists = useArtists("Arijit Singh");
  const playlists = usePlaylists("hits"); // 👈 NEW: fetch featured/popular playlists

  return (
    <>
      {/* Hero Section */}
      <section className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-emerald-500/60 via-green-800/50 to-zinc-900 p-7 shadow-glow md:p-12">
        <div className="relative z-10 max-w-xl">
          <p className="mb-3 text-sm font-bold uppercase tracking-[.2em] text-green-200">
            Your sound, amplified
          </p>
          <h1 className="text-4xl font-black leading-tight md:text-6xl">
            Music for every moment.
          </h1>
          <p className="mt-4 text-zinc-200">
            Discover millions of songs, playlists and artists—all in one
            beautiful place.
          </p>
          <Link
            href="/search"
            className="mt-7 inline-flex items-center gap-2 rounded-full bg-brand px-5 py-3 font-bold text-black transition hover:scale-105"
          >
            <Search size={18} /> Find your sound
          </Link>
        </div>
        <div className="absolute -right-24 -top-24 size-72 rounded-full bg-brand/30 blur-3xl" />
      </section>

      {/* 🆕 Playlists Section */}
      <RecentlyPlayed />
      <section className="mt-10">
        <h2 className="mb-5 text-2xl font-black">Featured playlists</h2>
        {playlists.isLoading ? (
          <CardsShimmer />
        ) : playlists.isError ? (
          <p className="text-zinc-400">
            Couldn’t load playlists. Please try again.
          </p>
        ) : (
          <Cards items={playlists.data?.results || []} type="playlist" />
        )}
      </section>

      {/* Albums Section */}
      <section className="mt-10">
        <h2 className="mb-5 text-2xl font-black">Popular albums</h2>
        {albums.isLoading ? (
          <CardsShimmer />
        ) : albums.isError ? (
          <p className="text-zinc-400">
            Couldn’t load albums. Please try again.
          </p>
        ) : (
          <Cards items={albums.data?.results || []} type="album" />
        )}
      </section>

      {/* Songs Section */}
      <section className="mt-10">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-2xl font-black">Made for you</h2>
          <Link
            href="/search"
            className="flex items-center gap-1 text-sm font-bold text-brand"
          >
            See all <ArrowRight size={15} />
          </Link>
        </div>
        {songs.isLoading ? (
          <CardsShimmer />
        ) : songs.isError ? (
          <p className="text-zinc-400">
            Couldn’t load songs. Please try again.
          </p>
        ) : (
          <SongList songs={(songs.data?.results || []).slice(0, 8)} />
        )}
      </section>

      {/* Artists Section */}
      <section className="mt-10">
        <h2 className="mb-5 text-2xl font-black">Featured artists</h2>
        {artists.isLoading ? (
          <CardsShimmer />
        ) : (
          <Cards
            items={(artists.data?.results || []).slice(0, 5)}
            type="artist"
          />
        )}
      </section>
    </>
  );
}
