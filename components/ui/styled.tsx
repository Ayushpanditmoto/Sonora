"use client";

import styled, { css } from "styled-components";

export const BrandButton = styled.button`
  display: inline-flex; align-items: center; justify-content: center; gap: .5rem;
  border: 0; border-radius: 999px; padding: .8rem 1.25rem; font-weight: 800;
  color: #06140b; background: #1ed760; cursor: pointer;
  box-shadow: 0 8px 24px rgb(30 215 96 / .18); transition: transform .18s ease, box-shadow .18s ease;
  &:hover { transform: translateY(-2px) scale(1.02); box-shadow: 0 12px 30px rgb(30 215 96 / .30); }
  &:active { transform: scale(.97); }
  &:disabled { cursor: not-allowed; opacity: .45; transform: none; }
`;

export const IconAction = styled.button<{ $active?: boolean }>`
  display: grid; place-items: center; width: 2.25rem; height: 2.25rem; border: 0; border-radius: 999px;
  color: ${({ $active }) => $active ? "#1ed760" : "#a7a7a7"}; background: transparent; cursor: pointer;
  transition: color .18s ease, background .18s ease, transform .18s ease;
  &:hover { color: #fff; background: rgb(255 255 255 / .1); transform: scale(1.08); }
  &:disabled { opacity: .4; cursor: not-allowed; }
`;

export const PlayerPlayButton = styled(BrandButton)`
  width: 2.75rem; height: 2.75rem; padding: 0; color: #000; background: #fff; box-shadow: none;
  &:hover { color: #000; background: #1ed760; }
`;

export const ProgressTrack = styled.input.attrs({ type: "range" })`
  height: 4px; flex: 1; appearance: none; border-radius: 999px; cursor: pointer; background: #4d4d4d;
  &::-webkit-slider-thumb { width: 12px; height: 12px; appearance: none; border-radius: 999px; background: #1ed760; box-shadow: 0 0 0 3px rgb(30 215 96 / .15); }
  &::-moz-range-thumb { width: 12px; height: 12px; border: 0; border-radius: 999px; background: #1ed760; }
`;
