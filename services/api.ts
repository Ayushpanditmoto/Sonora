import axios from "axios";
import type { Album, Artist, Detail, Playlist, SearchResults, Song } from "@/types/music";

const client = axios.create({
  baseURL: "/api/saavn",
  timeout: 15000,
});

const unwrap = <T>(path: string, params?: Record<string, string | number>) =>
  client.get<Detail<T>>(path, { params }).then(r => r.data.data);

export const saavn = {
  globalSearch: (query: string) =>
    unwrap<Record<string, unknown>>("/search", { query }),

  searchSongs: (query: string, page = 0, limit = 20) =>
    unwrap<SearchResults<Song>>("/search/songs", { query, page, limit }),

  searchAlbums: (query: string, page = 0, limit = 20) =>
    unwrap<SearchResults<Album>>("/search/albums", { query, page, limit }),

  searchArtists: (query: string) =>
    unwrap<SearchResults<Artist>>("/search/artists", { query }),

  searchPlaylists: (query: string) =>
    unwrap<SearchResults<Playlist>>("/search/playlists", { query }),

  song: (id: string) =>
    unwrap<Song[]>(`/songs/${id}`),

  songs: (ids: string[]) =>
    unwrap<Song[]>("/songs", { id: ids.join(",") }),

  suggestions: (id: string) =>
    unwrap<Song[]>(`/songs/${id}/suggestions`),

  album: (id: string) =>
    unwrap<Album & { songs?: Song[] }>("/albums", { id }),

  artist: (id: string) =>
    unwrap<Artist & { topSongs?: Song[]; songs?: Song[]; albums?: Album[] }>("/artists", { id }),

  playlist: (id: string) =>
    unwrap<Playlist>("/playlists", { id }),
};