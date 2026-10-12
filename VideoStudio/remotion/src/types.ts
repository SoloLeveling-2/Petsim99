export type Rect = {x: number; y: number; w: number; h: number};

export type CounterKey = {t: number; value: number; delta?: number};
export type ClockKey = {t: number; src_t: number};
export type QuestPopData = {t: number; stars: number; status: string; name: string | null; label: string};

export type Overlay = {
	hook: {start: number; end: number; text: string; sub: string};
	counter: CounterKey[];
	clock: ClockKey[];
	speedups: {start: number; end: number; speed: number}[];
	quests: QuestPopData[];
	rank_ups: {t: number; to_total: number | null}[];
	disclosure: {
		text: string;
		title: string;
		body: string;
		card_start: number;
		card_end: number;
		badge_start: number;
		badge_end: number;
	};
	outro: {
		start: number;
		end: number;
		total: number | null;
		quests: number;
		rank_ups: number;
		minutes: number;
		cta: string;
		handle: string;
	};
};

export type Brand = {
	colors: {primary: string; accent: string; highlight: string; danger: string; ink: string; paper: string};
	font: {family: string; file?: string; license?: string};
	channel_name: string;
};

export type Layout = {
	mode: string;
	main_rect: Rect;
	panel_rect: Rect | null;
	star_rect: Rect | null;
	panel_roi?: unknown;
	star_roi?: unknown;
};

export type OverlayProps = {
	width: number;
	height: number;
	fps: number;
	duration: number;
	overlay: Overlay;
	layout: Layout;
	brand: Brand;
};
