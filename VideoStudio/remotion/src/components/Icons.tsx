import React from 'react';

const STAR_POINTS = Array.from({length: 10}, (_, i) => {
	const angle = -Math.PI / 2 + (i * Math.PI) / 5;
	const r = i % 2 === 0 ? 50 : 22;
	return `${50 + r * Math.cos(angle)},${50 + r * Math.sin(angle)}`;
}).join(' ');

export const StarIcon: React.FC<{size: number; fill?: string}> = ({size, fill = '#FFC83D'}) => (
	<svg width={size} height={size} viewBox="-6 -6 112 112" style={{overflow: 'visible'}}>
		<polygon points={STAR_POINTS} fill={fill} stroke="#14121F" strokeWidth={8} strokeLinejoin="round" />
		<polygon points={STAR_POINTS} fill="rgba(255,255,255,0.35)" transform="translate(14 10) scale(0.55)" />
	</svg>
);

export const CheckIcon: React.FC<{size: number; color?: string}> = ({size, color = '#FFFFFF'}) => (
	<svg width={size} height={size} viewBox="0 0 100 100">
		<circle cx={50} cy={50} r={46} fill="#14121F" />
		<path d="M27 52 L44 68 L74 34" fill="none" stroke={color} strokeWidth={12} strokeLinecap="round" strokeLinejoin="round" />
	</svg>
);

export const GemIcon: React.FC<{size: number}> = ({size}) => (
	<svg width={size} height={size} viewBox="0 0 100 100">
		<polygon points="50,6 90,36 50,94 10,36" fill="#4FD1FF" stroke="#14121F" strokeWidth={7} strokeLinejoin="round" />
		<polygon points="50,6 66,36 50,94 34,36" fill="#A7ECFF" />
		<line x1={10} y1={36} x2={90} y2={36} stroke="#14121F" strokeWidth={5} />
	</svg>
);

export const ClockIcon: React.FC<{size: number}> = ({size}) => (
	<svg width={size} height={size} viewBox="0 0 100 100">
		<circle cx={50} cy={50} r={42} fill="#FFFFFF" stroke="#14121F" strokeWidth={9} />
		<path d="M50 24 V52 L68 62" fill="none" stroke="#14121F" strokeWidth={9} strokeLinecap="round" />
	</svg>
);

export const FastForwardIcon: React.FC<{size: number}> = ({size}) => (
	<svg width={size} height={size} viewBox="0 0 100 100">
		<polygon points="8,20 50,50 8,80" fill="#14121F" />
		<polygon points="50,20 92,50 50,80" fill="#14121F" />
	</svg>
);
