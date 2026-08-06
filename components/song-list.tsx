"use client";
import Image from "next/image";
// Link intentionally removed — titles now play the song; use the song page button if needed
import { Download, Heart, MoreHorizontal, Play } from "lucide-react";
import { useState } from "react";
import type { Song } from "@/types/music";
import { artistNames, decodeHtml, duration, imageUrl } from "@/lib/utils";
import { usePlayer } from "@/store/player";
import { downloadSong } from "@/lib/download";
export function SongList({ songs }: { songs: Song[] }) {
  const { setCurrent, current, favorites, toggleFavorite } = usePlayer();
  const [downloading, setDownloading] = useState<string>();
  const download = async (song: Song) => {
    try {
      setDownloading(song.id);
      await downloadSong(song);
    } catch {
      window.alert("This track could not be downloaded.");
    } finally {
      setDownloading(undefined);
    }
  };
  return (
    <div className="divide-y divide-white/5">
      {songs.map((song, i) => {
        const liked = favorites.some((s) => s.id === song.id);
        return (
          <div
            key={song.id}
            className="group flex items-center gap-3 rounded-md px-2 py-2 hover:bg-white/10"
          >
            <button
              className="grid w-6 place-items-center text-sm text-zinc-400 hover:text-brand"
              onClick={() => setCurrent(song, songs)}
            >
              {current?.id === song.id ? (
                <Play size={16} fill="currentColor" />
              ) : (
                i + 1
              )}
            </button>
            <Image
              src={imageUrl(song.image)}
              alt=""
              width={44}
              height={44}
              className="size-11 rounded object-cover"
            />
            <div className="min-w-0 flex-1">
              <button
                onClick={() => setCurrent(song, songs)}
                className="block w-full text-left truncate text-sm font-medium hover:underline"
              >
                {decodeHtml(song.name)}
              </button>
              <p className="truncate text-xs text-zinc-400">
                {artistNames(song.artists)}
              </p>
              {typeof song.playCount === "number" ? (
                <p className="mt-1 text-xs text-zinc-500">
                  {song.playCount.toLocaleString()} plays
                </p>
              ) : null}
            </div>
            <span className="hidden max-w-48 truncate text-sm text-zinc-400 sm:block">
              {song.album?.name ? decodeHtml(song.album.name) : ""}
            </span>
            <button
              aria-label="Download song"
              disabled={!song.downloadUrl?.length || downloading === song.id}
              onClick={() => download(song)}
              className="text-zinc-500 opacity-0 transition hover:text-white group-hover:opacity-100 disabled:cursor-not-allowed disabled:opacity-30"
            >
              <Download
                size={17}
                className={downloading === song.id ? "animate-pulse" : ""}
              />
            </button>
            <button
              onClick={() => toggleFavorite(song)}
              className={
                liked
                  ? "text-brand"
                  : "text-zinc-500 opacity-0 group-hover:opacity-100"
              }
            >
              <Heart size={17} fill={liked ? "currentColor" : "none"} />
            </button>
            <div className="flex w-28 flex-col items-end text-xs text-zinc-500">
              <span className="text-right">{duration(song.duration)}</span>
            </div>
            <MoreHorizontal className="text-zinc-500" size={18} />
          </div>
        );
      })}
    </div>
  );
}
