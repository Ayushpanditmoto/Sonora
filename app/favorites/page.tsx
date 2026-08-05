"use client";
import { Heart } from "lucide-react";
import { SongList } from "@/components/song-list";
import { usePlayer } from "@/store/player";
export default function FavoritesPage() { const favorites = usePlayer(s => s.favorites); return <><div className="flex items-end gap-5 rounded-xl bg-gradient-to-br from-violet-700 to-zinc-900 p-7 md:p-12"><div className="grid size-24 place-items-center rounded bg-gradient-to-br from-violet-300 to-violet-700 shadow-lg"><Heart size={42} fill="white"/></div><div><p className="text-sm font-bold">PLAYLIST</p><h1 className="text-4xl font-black md:text-6xl">Liked Songs</h1><p className="mt-3 text-sm text-zinc-300">{favorites.length} saved tracks</p></div></div><div className="mt-8">{favorites.length ? <SongList songs={favorites}/> : <p className="rounded-lg bg-white/5 p-8 text-zinc-400">Your liked songs will appear here. Tap the heart on any track to save it.</p>}</div></> }
