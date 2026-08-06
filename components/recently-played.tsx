"use client";
import { useMemo } from "react";
import { usePlayer } from "@/store/player";
import { SongList } from "@/components/song-list";
import type { Song } from "@/types/music";

interface RecentlyPlayedProps {
  emptyMessage?: string; // Optional: show this when no songs
}

export function RecentlyPlayed({ emptyMessage }: RecentlyPlayedProps) {
  const recently = usePlayer((s) => s.recentlyPlayed);
  const clear = usePlayer((s) => s.clearRecentlyPlayed);

  // If no songs and we have an emptyMessage, show it instead of returning null
  if (!recently || recently.length === 0) {
    if (emptyMessage) {
      return (
        <section className="mt-10">
          <h2 className="text-2xl font-black">Recently played</h2>
          <p className="mt-4 text-zinc-400">{emptyMessage}</p>
        </section>
      );
    }
    return null; // Home page → hide section
  }

  // Dedupe and sort newest first
  const unique = useMemo(() => {
    const seen = new Set<string>();
    const deduped = recently.filter((song) => {
      if (seen.has(song.id)) return false;
      seen.add(song.id);
      return true;
    });
    return deduped.reverse();
  }, [recently]);

  const handleClear = () => {
    if (window.confirm("Clear your recently played list?")) {
      clear();
    }
  };

  return (
    <section className="mt-10">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black">Recently played</h2>
        <button
          onClick={handleClear}
          className="text-sm text-zinc-400 hover:text-white transition-colors"
        >
          Clear
        </button>
      </div>
      <div className="mt-4">
        <SongList songs={unique} />
      </div>
    </section>
  );
}
