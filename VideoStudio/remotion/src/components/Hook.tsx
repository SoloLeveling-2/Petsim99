import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {dropShadow, outlined} from '../theme';
import {Brand} from '../types';

// One line if short, otherwise two lines of similar length (ties put more words first).
export const balancedLines = (words: string[], maxChars = 14): string[][] => {
	if (words.join(' ').length <= maxChars || words.length < 2) return [words];
	let best = 1;
	let bestScore = Infinity;
	for (let i = 1; i < words.length; i++) {
		const diff = Math.abs(words.slice(0, i).join(' ').length - words.slice(i).join(' ').length);
		if (diff <= bestScore) {
			best = i;
			bestScore = diff;
		}
	}
	return [words.slice(0, best), words.slice(best)];
};

// Opening hook: words punch in one after another, numbers in the brand's primary colour.
export const Hook: React.FC<{text: string; sub: string; durationInFrames: number; brand: Brand}> = ({
	text,
	sub,
	durationInFrames,
	brand,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const words = text.split(' ');
	const size = Math.max(84, Math.min(124, 1500 / Math.max(10, text.length)));
	const exit = interpolate(frame, [durationInFrames - 8, durationInFrames], [1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	const subIn = spring({frame: frame - words.length * 3 - 4, fps, config: {damping: 14, stiffness: 160}});

	return (
		<div
			style={{
				position: 'absolute',
				top: 150,
				left: 60,
				right: 60,
				display: 'flex',
				flexDirection: 'column',
				alignItems: 'center',
				gap: 8,
				opacity: exit,
				scale: String(0.92 + 0.08 * exit),
			}}
		>
			{balancedLines(words).map((line, row, rows) => (
			<div key={row} style={{display: 'flex', justifyContent: 'center', columnGap: 22, filter: dropShadow}}>
				{line.map((word, j) => {
					const i = rows.slice(0, row).reduce((n, r) => n + r.length, 0) + j;
					const s = spring({frame: frame - i * 3, fps, config: {damping: 11, stiffness: 190}});
					const isNumber = /[+\d]/.test(word);
					return (
						<span
							key={i}
							style={{
								...outlined(isNumber ? brand.colors.primary : brand.colors.paper, 18, brand.colors.ink),
								fontSize: size,
								display: 'inline-block',
								opacity: Math.min(1, s * 1.5),
								scale: String(0.4 + 0.6 * s),
								translate: `0 ${(1 - s) * 50}px`,
							}}
						>
							{word}
						</span>
					);
				})}
			</div>
			))}
			<div
				style={{
					...outlined(brand.colors.paper, 0),
					fontSize: 44,
					background: brand.colors.highlight,
					border: `5px solid ${brand.colors.ink}`,
					borderRadius: 999,
					padding: '10px 30px 14px',
					opacity: subIn,
					translate: `0 ${(1 - subIn) * 30}px`,
				}}
			>
				{sub}
			</div>
		</div>
	);
};
