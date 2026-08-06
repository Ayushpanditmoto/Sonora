"use client";
import { use } from "react";
import { useAlbum } from "@/hooks/use-music";
import { DetailHero } from "@/components/detail-hero";
import { SongList } from "@/components/song-list";
import { artistNames } from "@/lib/utils";
import { PageShimmer, ErrorFallback } from "@/components/loading-shimmer"; // adjust path

export default function AlbumPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const q = useAlbum(id);

  if (q.isLoading) return <PageShimmer />; // ✅ no extra wrapper
  if (q.isError || !q.data)
    return (
      <ErrorFallback message="Album unavailable." onRetry={() => q.refetch()} />
    );

  const album = q.data;
  return (
    <>
      <DetailHero
        type="Album"
        title={album.name}
        image={album.image}
        subtitle={`${artistNames(album.artists)} · ${album.year || ""}`}
        songs={album.songs || []}
      />
      <section className="mt-8">
        <SongList songs={album.songs || []} />
      </section>
    </>
  );
}
