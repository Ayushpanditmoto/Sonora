"use client";
import { use } from "react";
import { useSong, useSuggestions } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
import { artistNames } from "@/lib/utils";
export default function SongPage({ params }: { params: Promise<{ id: string }> }) { const { id } = use(params); const song = useSong(id); const related = useSuggestions(id); if (song.isLoading) return <p className="animate-pulse text-zinc-400">Loading track…</p>; if (song.isError || !song.data?.[0]) return <p className="text-red-300">Track unavailable.</p>; const track = song.data[0]; return <><DetailHero type="Song" title={track.name} image={track.image} subtitle={`${artistNames(track.artists)} · ${track.album?.name || "Single"}`} songs={[track]}/><section className="mt-10"><h2 className="mb-4 text-2xl font-black">More like this</h2>{related.isLoading ? <div className="space-y-3">{Array.from({ length: 7 }).map((_, i) => <div key={i} className="shimmer h-14 rounded"/>)}</div> : related.isError ? <p className="text-zinc-400">Couldn’t load suggestions.</p> : <SongList songs={(related.data || []).filter(s => s.id !== id).slice(0, 10)}/>}</section></> }
