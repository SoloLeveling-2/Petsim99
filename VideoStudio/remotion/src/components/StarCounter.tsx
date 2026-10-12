import React from 'react';
import {Easing, interpolate, random, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {clamp01, outlined} from '../theme';
import {Brand, CounterKey, Rect} from '../types';
import {StarIcon} from './Icons';

const COUNT_UP_S = 0.6;

// Value shown at time t: counts up from the previous verified total after each keyframe.
export const counterValueAt = (keys: CounterKey[], t: number) => {
	let i = -1;
	for (let k = 0; k < keys.length; k++) {
		if (keys[k].t <= t) i = k;
	}
	if (i < 0) return null;
	const prev = i > 0 ? keys[i - 1].value : keys[i].value;
	const p = Easing.out(Easing.cubic)(clamp01((t - keys[i].t) / COUNT_UP_S));
	return Math.round(prev + (keys[i].value - prev) * p);
};

// Running total of rank stars counted on screen, pinned over the gameplay's top-left.
export const StarCounter: React.FC<{keys: CounterKey[]; start: number; end: number; main: Rect; brand: Brand}> = ({
	keys,
	start,
	end,
	main,
	brand,
}) => {
	const frame = useCurrentFrame();
	const {fps} = useVideoConfig();
	const t = start + frame / fps;
	const value = counterValueAt(keys, t) ?? 0;
	const enter = spring({frame, fps, config: {damping: 14}});
	const exit = interpolate(t, [end - 0.3, end], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
	const gains = keys.filter((k) => (k.delta ?? 0) > 0 && k.t <= t && t - k.t < 1.4);
	const latest = gains[gains.length - 1];
	const pulse = latest ? spring({frame: Math.round((t - latest.t) * fps), fps, config: {damping: 6, stiffness: 220}}) : 1;

	return (
		<div
			style={{
				position: 'absolute',
				left: main.x + 28,
				top: main.y + 24,
				display: 'flex',
				alignItems: 'center',
				gap: 14,
				background: 'rgba(20,18,31,0.84)',
				border: `5px solid ${brand.colors.primary}`,
				borderRadius: 28,
				padding: '12px 26px 12px 14px',
				opacity: enter * exit,
				translate: `${(1 - enter) * -60}px 0`,
			}}
		>
			<div style={{position: 'relative', width: 88, height: 88}}>
				<div style={{scale: String(latest ? 0.8 + 0.2 * pulse + 0.25 * (1 - pulse) : 1)}}>
					<StarIcon size={88} fill={brand.colors.primary} />
				</div>
				{latest
					? Array.from({length: 10}, (_, i) => {
							const age = t - latest.t;
							const angle = random(`a${latest.t}-${i}`) * Math.PI * 2;
							const dist = 40 + 90 * Easing.out(Easing.quad)(clamp01(age / 0.9));
							return (
								<div
									key={i}
									style={{
										position: 'absolute',
										left: 30 + Math.cos(angle) * dist,
										top: 30 + Math.sin(angle) * dist,
										opacity: 1 - clamp01(age / 0.9),
										scale: String(0.25 + random(`s${latest.t}-${i}`) * 0.25),
									}}
								>
									<StarIcon size={28} fill={brand.colors.primary} />
								</div>
							);
						})
					: null}
			</div>
			<div style={{display: 'flex', flexDirection: 'column', gap: 4}}>
				<span style={{...outlined(brand.colors.primary, 12, brand.colors.ink), fontSize: 84}}>+{value}</span>
				<span style={{...outlined(brand.colors.paper, 0), fontSize: 24, opacity: 0.9}}>RANK STARS THIS RUN</span>
			</div>
			{latest ? (
				<span
					style={{
						...outlined(brand.colors.accent, 10, brand.colors.ink),
						position: 'absolute',
						right: -96,
						top: 10 - 50 * clamp01((t - latest.t) / 1.2),
						fontSize: 64,
						opacity: 1 - clamp01((t - latest.t - 0.6) / 0.6),
					}}
				>
					+{latest.delta}
				</span>
			) : null}
		</div>
	);
};
