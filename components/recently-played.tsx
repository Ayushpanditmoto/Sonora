"use client";
import { usePlayer } from "@/store/player";
import { SongList } from "@/components/song-list";
import type { Song } from "@/types/music";
export function RecentlyPlayed() {
  const recently = usePlayer((s) => s.recentlyPlayed);
  const clear = usePlayer((s) => s.clearRecentlyPlayed);
  if (!recently || recently.length === 0) return null;

  // dedupe by id while preserving order
  const unique = recently.reduce((acc: typeof recently, item) => {
    if (!acc.find((x) => x.id === item.id)) acc.push(item);
    return acc;
  }, [] as Song[]);

  return (
    <section className="mt-10">
      <div className="flex items-center justify-between">
        <h2 className="text-2xl font-black">Recently played</h2>
        <button
          onClick={clear}
          className="text-sm text-zinc-400 hover:text-white"
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
