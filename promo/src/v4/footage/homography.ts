// CSS matrix3d that maps the rectangle (0,0)-(w,h) onto any four corners (clockwise from the
// top left): a projective transform, so a flat screen seen at an angle reads as one.

/** Solves the 3x3 projective transform taking the unit square to the quad. */
const squareToQuad = (q: [number, number][]) => {
  const [[x0, y0], [x1, y1], [x2, y2], [x3, y3]] = q;
  const dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
  const sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3;
  const det = dx1 * dy2 - dx2 * dy1;
  const g = (sx * dy2 - dx2 * sy) / det;
  const h = (dx1 * sy - sx * dy1) / det;
  return [
    [x1 - x0 + g * x1, x3 - x0 + h * x3, x0],
    [y1 - y0 + g * y1, y3 - y0 + h * y3, y0],
    [g, h, 1],
  ];
};

export const quadToCss = (w: number, h: number, q: [number, number][]) => {
  const m = squareToQuad(q);
  // scale the rectangle to the unit square first
  const a = [
    [m[0][0] / w, m[0][1] / h, m[0][2]],
    [m[1][0] / w, m[1][1] / h, m[1][2]],
    [m[2][0] / w, m[2][1] / h, m[2][2]],
  ];
  // column major 4x4 with z passed through
  const v = [a[0][0], a[1][0], 0, a[2][0], a[0][1], a[1][1], 0, a[2][1], 0, 0, 1, 0, a[0][2], a[1][2], 0, a[2][2]];
  return `matrix3d(${v.map((x) => x.toFixed(10)).join(",")})`;
};

/** Where a point (u, v) in 0..1 of the rectangle lands inside the quad. */
export const quadPoint = (q: [number, number][], u: number, v: number) => {
  const m = squareToQuad(q);
  const X = m[0][0] * u + m[0][1] * v + m[0][2];
  const Y = m[1][0] * u + m[1][1] * v + m[1][2];
  const W = m[2][0] * u + m[2][1] * v + m[2][2];
  return { x: X / W, y: Y / W };
};
