import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { Song } from "@/types/music";
type State = {
  current?: Song;
  queue: Song[];
  isPlaying: boolean;
  favorites: Song[];
  setCurrent: (song: Song, queue?: Song[]) => void;
  previous: () => void;
  toggle: () => void;
  next: () => void;
  toggleFavorite: (song: Song) => void;
  clearPlayer: () => void;
};
export const usePlayer = create<State>()(
  persist(
    (set, get) => ({
      queue: [],
      isPlaying: false,
      favorites: [],
      previous: () => {
        const { current, queue } = get();
        const i = queue.findIndex((s) => s.id === current?.id);
        if (queue[i - 1]) set({ current: queue[i - 1], isPlaying: true });
      },
      setCurrent: (current, queue = get().queue) =>
        set({ current, queue, isPlaying: true }),
      toggle: () => set((s) => ({ isPlaying: !s.isPlaying })),
      next: () => {
        const { current, queue } = get();
        const i = queue.findIndex((s) => s.id === current?.id);
        if (queue[i + 1]) set({ current: queue[i + 1], isPlaying: true });
      },
      toggleFavorite: (song) =>
        set((s) => ({
          favorites: s.favorites.some((x) => x.id === song.id)
            ? s.favorites.filter((x) => x.id !== song.id)
            : [...s.favorites, song],
        })),
      clearPlayer: () => set({ current: undefined, queue: [], isPlaying: false }),
    }),
    {
      name: "sonora-player",
      partialize: (state) => ({ favorites: state.favorites }),
    }
  )
);
