class_name Tipos
## Tipos elementales compartidos por especies y movimientos.

enum Tipo {
	NORMAL, FUEGO, AGUA, PLANTA, ELECTRICO, HIELO, LUCHA, VENENO, TIERRA,
	VOLADOR, PSIQUICO, BICHO, ROCA, FANTASMA, DRAGON, SINIESTRO, ACERO, HADA,
}

## Id de cada tipo en el juego original (TipoName, frame de spr_gotype), en el orden de Tipo.
const ID_ORIGINAL: Array[int] = [1, 2, 3, 4, 5, 12, 7, 10, 8, 15, 9, 11, 6, 16, 17, 13, 14, 18]
