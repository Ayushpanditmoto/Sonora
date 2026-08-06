"use client";
import { use } from "react";
import { usePlaylist } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
import { PageShimmer, ErrorFallback } from "@/components/loading-shimmer";
export default function PlaylistPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const q = usePlaylist(id);
  if (q.isLoading) return <PageShimmer />; // ✅ no extra wrapper
  if (q.isError || !q.data)
    return (
      <ErrorFallback
        message="Playlist unavailable."
        onRetry={() => q.refetch()}
      />
    );
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
