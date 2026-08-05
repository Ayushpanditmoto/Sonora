import axios from "axios";
import type { Album, Artist, Detail, Playlist, SearchResults, Song } from "@/types/music";

const client = axios.create({ baseURL: "https://saavn.sumit.co", timeout: 15000 });
const unwrap = <T>(path: string, params?: Record<string, string | number>) => client.get<Detail<T>>(path, { params }).then(r => r.data.data);

export const saavn = {
  globalSearch: (query: string) => unwrap<Record<string, unknown>>("/api/search", { query }),
  searchSongs: (query: string, page = 0, limit = 20) => unwrap<SearchResults<Song>>("/api/search/songs", { query, page, limit }),
  searchAlbums: (query: string, page = 0, limit = 20) => unwrap<SearchResults<Album>>("/api/search/albums", { query, page, limit }),
  searchArtists: (query: string) => unwrap<SearchResults<Artist>>("/api/search/artists", { query }),
  searchPlaylists: (query: string) => unwrap<SearchResults<Playlist>>("/api/search/playlists", { query }),
  song: (id: string) => unwrap<Song[]>(`/api/songs/${id}`),
  songs: (ids: string[]) => unwrap<Song[]>("/api/songs", { id: ids.join(",") }),
  suggestions: (id: string) => unwrap<Song[]>(`/api/songs/${id}/suggestions`),
  album: (id: string) => unwrap<Album & { songs?: Song[] }>("/api/albums", { id }),
  artist: (id: string) => unwrap<Artist & { topSongs?: Song[]; songs?: Song[]; albums?: Album[] }>("/api/artists", { id }),
  playlist: (id: string) => unwrap<Playlist>("/api/playlists", { id })
};
