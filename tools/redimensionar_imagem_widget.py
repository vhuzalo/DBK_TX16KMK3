#!/usr/bin/env python3
"""Prepara uma imagem PNG de modelo para o widget DBK_TX16KMK3.

Mantém a proporção da imagem, reduz (ou amplia) para caber em 250x150 px
e centraliza o resultado sobre fundo preto, que combina com o widget.
Opcionalmente, remove o fundo da imagem antes de prepará-la.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

LARGURA = 250
ALTURA = 150


def remover_fundo(imagem: Image.Image) -> Image.Image:
    try:
        from rembg import remove
    except ModuleNotFoundError as erro:
        raise RuntimeError(
            "Para usar --remover-fundo, instale a dependência com: "
            "python3 -m pip install rembg"
        ) from erro

    resultado = remove(imagem)
    return resultado.convert("RGBA")


def converter(entrada: Path, saida: Path, deve_remover_fundo: bool) -> None:
    with Image.open(entrada) as original:
        imagem = original.convert("RGBA")
        if deve_remover_fundo:
            imagem = remover_fundo(imagem)
        imagem.thumbnail((LARGURA, ALTURA), Image.Resampling.LANCZOS)

        # A tela RGB, sem canal alfa, é mais compatível com o Bitmap.open()
        # do EdgeTX do que PNGs produzidos com transparência pelo Pillow.
        tela = Image.new("RGB", (LARGURA, ALTURA), (0, 0, 0))
        posicao = (
            (LARGURA - imagem.width) // 2,
            (ALTURA - imagem.height) // 2,
        )
        tela.paste(imagem, posicao, imagem)

    saida.parent.mkdir(parents=True, exist_ok=True)
    tela.save(saida, "PNG", optimize=True)
    print(f"Criado: {saida} ({LARGURA}x{ALTURA}px)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cria um PNG de 250x150 px para o DBK_TX16KMK3."
    )
    parser.add_argument("entrada", type=Path, help="imagem original (JPG, PNG, WEBP etc.)")
    parser.add_argument(
        "saida",
        type=Path,
        nargs="?",
        help="PNG de saída (padrão: <nome>_dbk.png)",
    )
    parser.add_argument(
        "--remover-fundo",
        action="store_true",
        help="remove automaticamente o fundo antes de gerar o PNG",
    )
    args = parser.parse_args()

    if not args.entrada.is_file():
        parser.error(f"arquivo de entrada não encontrado: {args.entrada}")

    saida = args.saida or args.entrada.with_name(f"{args.entrada.stem}_dbk.png")
    try:
        converter(args.entrada, saida.with_suffix(".png"), args.remover_fundo)
    except RuntimeError as erro:
        parser.error(str(erro))


if __name__ == "__main__":
    main()
