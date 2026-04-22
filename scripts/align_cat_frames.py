#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image


ALPHA_THRESHOLD = 10
FRAME_IDS = range(1, 9)
RESOURCE_DIR = Path(__file__).resolve().parents[1] / "Planit" / "Resources"


@dataclass(frozen=True)
class BBox:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top

    def shifted(self, dx: int, dy: int) -> "BBox":
        return BBox(
            left=self.left + dx,
            top=self.top + dy,
            right=self.right + dx,
            bottom=self.bottom + dy,
        )

    def as_tuple(self) -> tuple[int, int, int, int]:
        return (self.left, self.top, self.right, self.bottom)


@dataclass(frozen=True)
class AlignmentResult:
    name: str
    canvas_size: tuple[int, int]
    original_bbox: BBox
    offset: tuple[int, int]
    new_bbox: BBox


def alpha_bbox(image: Image.Image, threshold: int) -> BBox:
    mask = image.getchannel("A").point(lambda alpha: 255 if alpha > threshold else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("frame contains no visible pixels")

    return BBox(*bbox)


def align_group(frame_names: list[str]) -> list[AlignmentResult]:
    images: list[tuple[str, Image.Image, BBox]] = []
    canvas_width: int | None = None
    canvas_height: int | None = None

    for name in frame_names:
        path = RESOURCE_DIR / f"{name}.png"
        image = Image.open(path).convert("RGBA")
        bbox = alpha_bbox(image, ALPHA_THRESHOLD)
        images.append((name, image, bbox))

        if canvas_width is None:
            canvas_width, canvas_height = image.size
        elif image.size != (canvas_width, canvas_height):
            raise ValueError(f"inconsistent canvas size for {path.name}: {image.size}")

    assert canvas_width is not None
    assert canvas_height is not None

    common_bbox_width = max(bbox.width for _, _, bbox in images)
    if common_bbox_width > canvas_width:
        raise ValueError(
            f"common bbox width {common_bbox_width} exceeds canvas width {canvas_width}"
        )

    results: list[AlignmentResult] = []

    for name, image, bbox in images:
        cropped = image.crop(bbox.as_tuple())
        new_left = (canvas_width - bbox.width) // 2
        new_top = canvas_height - bbox.height
        offset = (new_left - bbox.left, new_top - bbox.top)

        canvas = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 0))
        canvas.paste(cropped, (new_left, new_top))
        canvas.save(RESOURCE_DIR / f"{name}.png")

        new_bbox = bbox.shifted(*offset)
        results.append(
            AlignmentResult(
                name=name,
                canvas_size=(canvas_width, canvas_height),
                original_bbox=bbox,
                offset=offset,
                new_bbox=new_bbox,
            )
        )

    return results


def main() -> None:
    groups = [
        [f"frame_R{index}" for index in FRAME_IDS],
        [f"frame_R{index}@2x" for index in FRAME_IDS],
    ]

    for frame_names in groups:
        results = align_group(frame_names)
        canvas = results[0].canvas_size
        max_width = max(result.original_bbox.width for result in results)
        print(f"[group] canvas={canvas[0]}x{canvas[1]} common_bbox_width={max_width}")
        for result in results:
            print(
                f"{result.name}.png "
                f"original_bbox={result.original_bbox.as_tuple()} "
                f"offset={result.offset} "
                f"new_bbox={result.new_bbox.as_tuple()}"
            )


if __name__ == "__main__":
    main()
