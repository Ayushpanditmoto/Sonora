"use client";
import { use } from "react";
import { useArtist } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
import { Cards } from "@/components/cards";
import { PageShimmer, ErrorFallback } from "@/components/loading-shimmer";
export default function ArtistPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const q = useArtist(id);
  if (q.isLoading) return <PageShimmer />;
  if (q.isError || !q.data)
    return (
      <ErrorFallback
        message="Artist unavailable."
        onRetry={() => q.refetch()}
      />
    );
  const artist = q.data;
  const songs = artist.topSongs || artist.songs || [];
  return (
    <>
      <DetailHero
        type="Artist"
        title={artist.name}
        image={artist.image}
        subtitle={artist.role || "Artist"}
        songs={songs}
      />
      <section className="mt-10">
        <h2 className="mb-4 text-2xl font-black">Popular</h2>
        <SongList songs={songs} />
      </section>
      {artist.albums?.length ? (
        <section className="mt-10">
          <h2 className="mb-4 text-2xl font-black">Albums</h2>
          <Cards items={artist.albums} type="album" />
        </section>
      ) : null}
    </>
  );
}
