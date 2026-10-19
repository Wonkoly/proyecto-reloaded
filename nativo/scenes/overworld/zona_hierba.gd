class_name ZonaHierba
extends Area2D
## Una zona de encuentros de un mapa: la hierba alta (obj_hierba), la hierba invisible
## (obj_hierbaInvisible) o el barro (obj_barro); un rectángulo por instancia. Qué subtabla de
## TablaEncuentros usa lo dice su método (ProtaCheckHierba → global.hierba).

@export var metodo: SubtablaEncuentros.Metodo = SubtablaEncuentros.Metodo.HIERBA
