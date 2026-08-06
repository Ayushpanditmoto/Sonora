"use client";
import { useMemo } from "react";
import { usePlayer } from "@/store/player";
import { SongList } from "@/components/song-list";

interface RecentlyPlayedProps {
  emptyMessage?: string;
}

export function RecentlyPlayed({ emptyMessage }: RecentlyPlayedProps) {
  // 1. All hooks called unconditionally at the top
  const recently = usePlayer((s) => s.recentlyPlayed);
  const clear = usePlayer((s) => s.clearRecentlyPlayed);

  // 2. Memoize deduped & reversed list (works even if recently is empty)
  const unique = useMemo(() => {
    if (!recently || recently.length === 0) return [];
    const seen = new Set<string>();
    const deduped = recently.filter((song) => {
      if (seen.has(song.id)) return false;
      seen.add(song.id);
      return true;
    });
    return deduped.reverse();
  }, [recently]);

  // 3. Now conditional rendering (after all hooks)
  if (unique.length === 0) {
    if (emptyMessage) {
      return (
        <section className="mt-10">
          <h2 className="text-2xl font-black">Recently played</h2>
          <p className="mt-4 text-zinc-400">{emptyMessage}</p>
        </section>
      );
    }
    return null;
  }

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
