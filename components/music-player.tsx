"use client";
import Image from "next/image";
import { Download, Heart, ListPlus, Pause, Play, SkipForward } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { usePlayer } from "@/store/player";
import { artistNames, duration, imageUrl } from "@/lib/utils";
import { downloadSong } from "@/lib/download";
import { IconAction, PlayerPlayButton, ProgressTrack } from "@/components/ui/styled";

export function MusicPlayer() {
  const { current, isPlaying, toggle, next, favorites, toggleFavorite } = usePlayer();
  const audio = useRef<HTMLAudioElement>(null);
  const [elapsed, setElapsed] = useState(0);
  const [total, setTotal] = useState(0);
  const [downloading, setDownloading] = useState(false);
  useEffect(() => { if (isPlaying) audio.current?.play().catch(() => undefined); else audio.current?.pause(); }, [isPlaying, current?.id]);
  if (!current) return null;
  const favorite = favorites.some(s => s.id === current.id);
  const seek = (value: number) => { if (audio.current) { audio.current.currentTime = value; setElapsed(value); } };
  const download = async () => { try { setDownloading(true); await downloadSong(current); } catch { window.alert("This track could not be downloaded."); } finally { setDownloading(false); } };
  return <footer className="fixed inset-x-0 bottom-0 z-40 border-t border-white/10 bg-zinc-950 px-3 py-2 md:px-6">
    <div className="absolute inset-x-0 top-0 flex items-center gap-2 px-3 text-[10px] text-zinc-400 md:px-6"><span>{duration(elapsed)}</span><ProgressTrack aria-label="Song progress" min="0" max={total || current.duration || 1} value={elapsed} onChange={e => seek(Number(e.target.value))}/><span>{duration(total || current.duration)}</span></div>
    <div className="relative mt-3 flex h-14 items-center gap-3"><Image src={imageUrl(current.image)} alt="" width={52} height={52} className="size-12 rounded object-cover"/><div className="min-w-0 flex-1 md:max-w-xs"><p className="truncate text-sm font-semibold">{current.name}</p><p className="truncate text-xs text-zinc-400">{artistNames(current.artists)}</p></div><div className="flex items-center gap-2 md:absolute md:left-1/2 md:-translate-x-1/2"><PlayerPlayButton aria-label={isPlaying ? "Pause" : "Play"} onClick={toggle}>{isPlaying ? <Pause size={18} fill="currentColor"/> : <Play size={18} fill="currentColor"/>}</PlayerPlayButton><IconAction aria-label="Next song" onClick={next} className="hidden sm:grid"><SkipForward size={20}/></IconAction></div><div className="ml-auto hidden items-center gap-2 md:flex"><IconAction aria-label="Download song" disabled={downloading || !current.downloadUrl?.length} onClick={download}><Download size={19} className={downloading ? "animate-pulse" : ""}/></IconAction><IconAction $active={favorite} aria-label="Like song" onClick={() => toggleFavorite(current)}><Heart size={20} fill={favorite ? "currentColor" : "none"}/></IconAction><IconAction as="span" aria-label="Add to queue"><ListPlus size={19}/></IconAction></div></div>
    <audio ref={audio} key={current.id} src={current.downloadUrl?.at(-1)?.url} onLoadedMetadata={e => setTotal(e.currentTarget.duration)} onTimeUpdate={e => setElapsed(e.currentTarget.currentTime)} onEnded={next}/>
  </footer>
}
