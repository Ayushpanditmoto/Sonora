"use client";
import Image from "next/image";
import { Play } from "lucide-react";
import type { Image as MusicImage, Song } from "@/types/music";
import { imageUrl } from "@/lib/utils";
import { usePlayer } from "@/store/player";
export function DetailHero({ type, title, image, subtitle, songs = [] }: { type: string; title: string; image?: MusicImage[]; subtitle: string; songs?: Song[] }) { const setCurrent = usePlayer(s => s.setCurrent); return <div className="flex flex-col gap-6 rounded-xl bg-gradient-to-b from-white/15 to-transparent p-6 md:flex-row md:items-end md:p-10"><Image src={imageUrl(image)} alt={title} width={240} height={240} className="size-48 rounded-md object-cover shadow-2xl md:size-56"/><div><p className="text-xs font-bold uppercase tracking-widest">{type}</p><h1 className="mt-2 text-4xl font-black leading-none md:text-6xl">{title}</h1><p className="mt-4 text-sm text-zinc-300">{subtitle}</p>{songs.length > 0 && <button onClick={() => setCurrent(songs[0], songs)} className="mt-6 inline-grid size-14 place-items-center rounded-full bg-brand text-black shadow-glow transition hover:scale-105"><Play fill="currentColor"/></button>}</div></div> }
