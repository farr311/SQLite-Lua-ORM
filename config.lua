if display.pixelHeight / display.pixelWidth < 1.5 then
	--tablet
	width = 720
	height = 720 * display.pixelHeight / display.pixelWidth
else
	--phone
	--width = 320
	--height = 320 * display.pixelHeight / display.pixelWidth
end

application = {
	content = {
		width = width,
		height = height, 
		scale = "letterbox",
		fps = 60,
	},
	license = {
		google = {
			--mapsKey = "AIzaSyAmkoYvIJc4Ifb1M1QrB3_s5kc7ska1AS0",
		},
	},
}