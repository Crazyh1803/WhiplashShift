extends MainMenu

var garage_requests := 0
var opened_links: Array[String] = []


func _open_garage() -> void:
	garage_requests += 1


func _open_url(url: String) -> void:
	opened_links.append(url)


func _open_link(url: String) -> void:
	opened_links.append(url)
