"use client";
import Image from "next/image";
import Link from "next/link";
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
              <Link
                href={`/song/${song.id}`}
                className="block truncate text-sm font-medium hover:underline"
              >
                {decodeHtml(song.name)}
              </Link>
              <p className="truncate text-xs text-zinc-400">
                {artistNames(song.artists)}
              </p>
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
            <span className="w-10 text-right text-xs text-zinc-500">
              {duration(song.duration)}
            </span>
            <MoreHorizontal className="text-zinc-500" size={18} />
          </div>
        );
      })}
    </div>
  );
}
