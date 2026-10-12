import {CSSProperties} from 'react';
import {loadFont} from '@remotion/fonts';
import {staticFile} from 'remotion';

export const FONT_FAMILY = 'Lilita One';

// Brand font (SIL OFL 1.1, see public/fonts/OFL.txt). loadFont holds the render until it is ready.
loadFont({family: FONT_FAMILY, url: staticFile('fonts/LilitaOne-Regular.ttf')});

export const sec = (seconds: number, fps: number) => Math.round(seconds * fps);

export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

export const outlined = (color: string, stroke: number, strokeColor = '#14121F'): CSSProperties => ({
	color,
	WebkitTextStroke: `${stroke}px ${strokeColor}`,
	paintOrder: 'stroke fill',
	fontFamily: FONT_FAMILY,
	lineHeight: 1.0,
	letterSpacing: 1,
});

export const dropShadow = 'drop-shadow(0 8px 0 rgba(0,0,0,0.35))';

export const formatClock = (seconds: number) => {
	const s = Math.max(0, Math.floor(seconds));
	return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};
