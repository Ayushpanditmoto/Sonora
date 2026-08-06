"use client";
import { use } from "react";
import { usePlaylist } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
export default function PlaylistPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const q = usePlaylist(id);
  if (q.isLoading)
    return <p className="animate-pulse text-zinc-400">Loading playlist…</p>;
  if (q.isError || !q.data)
    return <p className="text-red-300">Playlist unavailable.</p>;
  const playlist = q.data;
  return (
    <>
      <DetailHero
        type="Playlist"
        title={playlist.name}
        image={playlist.image}
        subtitle={`${playlist.songCount || playlist.songs?.length || 0} songs · ${playlist.description || "Listen now"}`}
        songs={playlist.songs || []}
      />
      <section className="mt-8">
        <SongList songs={playlist.songs || []} />
      </section>
    </>
  );
}
