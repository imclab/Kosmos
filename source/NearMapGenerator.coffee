root = exports ? this

class root.NearMapGenerator
	constructor: (mapResolution) ->
		# load shader
		@shader = xgl.loadProgram("nearMapGenerator")
		@shader.uniforms = xgl.getProgramUniforms(@shader, ["verticalViewport"])
		@shader.attribs = xgl.getProgramAttribs(@shader, ["aUV", "aPos", "aTangent", "aBinormal"])

		# initialize FBO
		@fbo = gl.createFramebuffer()
		gl.bindFramebuffer(gl.FRAMEBUFFER, @fbo)
		@fbo.width = mapResolution
		@fbo.height = mapResolution
		console.log("Initialized high resolution planet map generator FBO at #{@fbo.width} x #{@fbo.height}")
		gl.bindFramebuffer(gl.FRAMEBUFFER, null)

		# create fullscreen quad vertices
		buff = new Float32Array(6*6*11)
		i = 0
		tangent = [0, 0, 0]
		binormal = [0, 0, 0]
		for faceIndex in [0..5]
			for uv in [[0,0], [1,0], [0,1], [1,0], [1,1], [0,1]]
				pos = mapPlaneToCube(uv[0], uv[1], faceIndex)
				buff[i++] = uv[0]; buff[i++] = uv[1]
				buff[i++] = pos[0]; buff[i++] = pos[1]; buff[i++] = pos[2]
				posU = mapPlaneToCube(uv[0]+1, uv[1], faceIndex)
				posV = mapPlaneToCube(uv[0], uv[1]+1, faceIndex)
				binormal = [posU[0]-pos[0], posU[1]-pos[1], posU[2]-pos[2]]
				tangent = [posV[0]-pos[0], posV[1]-pos[1], posV[2]-pos[2]]
				buff[i++] = binormal[0]; buff[i++] = binormal[1]; buff[i++] = binormal[2]
				buff[i++] = tangent[0]; buff[i++] = tangent[1]; buff[i++] = tangent[2]

		@quadVerts = gl.createBuffer()
		gl.bindBuffer(gl.ARRAY_BUFFER, @quadVerts);
		gl.bufferData(gl.ARRAY_BUFFER, buff, gl.STATIC_DRAW)
		gl.bindBuffer(gl.ARRAY_BUFFER, null)
		@quadVerts.itemSize = 11
		@quadVerts.numItems = buff.length / @quadVerts.itemSize


	# call this before making call(s) to generateSubMap
	start: ->		
		gl.disable(gl.DEPTH_TEST)
		gl.depthMask(false)

		gl.useProgram(@shader)

		gl.bindFramebuffer(gl.FRAMEBUFFER, @fbo)
		gl.viewport(0, 0, @fbo.width, @fbo.height)

		gl.bindBuffer(gl.ARRAY_BUFFER, @quadVerts)
		gl.enableVertexAttribArray(@shader.attribs.aUV)
		gl.vertexAttribPointer(@shader.attribs.aUV, 2, gl.FLOAT, false, @quadVerts.itemSize*4, 0)
		gl.enableVertexAttribArray(@shader.attribs.aPos)
		gl.vertexAttribPointer(@shader.attribs.aPos, 3, gl.FLOAT, false, @quadVerts.itemSize*4, 4 *2)
		gl.enableVertexAttribArray(@shader.attribs.aBinormal)
		gl.vertexAttribPointer(@shader.attribs.aBinormal, 3, gl.FLOAT, false, @quadVerts.itemSize*4, 4 *5)
		gl.enableVertexAttribArray(@shader.attribs.aTangent)
		gl.vertexAttribPointer(@shader.attribs.aTangent, 3, gl.FLOAT, false, @quadVerts.itemSize*4, 4 *8)


	# call this after making call(s) to generateSubMap
	finish: ->
		gl.disableVertexAttribArray(@shader.attribs.aUV)
		gl.disableVertexAttribArray(@shader.attribs.aPos)
		gl.disableVertexAttribArray(@shader.attribs.aBinormal)
		gl.disableVertexAttribArray(@shader.attribs.aTangent)

		gl.bindBuffer(gl.ARRAY_BUFFER, null)
		gl.bindFramebuffer(gl.FRAMEBUFFER, null)

		gl.useProgram(null)

		gl.depthMask(true)
		gl.enable(gl.DEPTH_TEST)


	# Creates and returns a list of six opengl textures, mapping to each face of the planet cube
	# This list of opengl textures should be passed to generateSubMap() to progressively fill in map data
	createMaps: ->
		maps = []
		for face in [0..5]
			maps[face] = gl.createTexture()
			gl.bindTexture(gl.TEXTURE_2D, maps[face])
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_NEAREST)
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, @fbo.width, @fbo.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
		gl.bindTexture(gl.TEXTURE_2D, null)
		return maps


	# Call this to generate a subset of "maps", which is the list of gl images representing the 6 cube faces
	# "maps" should be created with the createMaps() function only, and passed in here unmodified.
	# "seed" represents the content seed towards generating this planet data. "faceIndex" specifies which face
	# of "maps" to update. "startFraction" and "endFraction" specify an interval between 0 and 1, representing
	# what part of the map to update. For example, if you update [0,1] then that will generate the entire face.
	# Generating [0,.5] will fill in the first half of the map, and [.5,1] the second half. This can be used
	# to generate any arbitrary subset of the image. (In the actual map this represents vertical intervals).
	generateSubMap: (maps, seed, faceIndex, startFraction, endFraction) ->
		# bind the appropriate face map texture
		dataMap = maps[faceIndex]
		gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, dataMap, 0)

		# select the subset of the viewport to generate
		gl.viewport(0, @fbo.height * startFraction, @fbo.width, @fbo.height * endFraction)
		gl.uniform2f(@shader.uniforms.verticalViewport, startFraction, endFraction - startFraction);

		# run the generation shader
		indicesPerFace = @quadVerts.numItems / 6
		gl.drawArrays(gl.TRIANGLES, indicesPerFace * faceIndex, indicesPerFace);


	# call t his to finalize map generation
	finalizeMaps: (maps) ->
		for i in [0..5]
			gl.bindTexture(gl.TEXTURE_2D, maps[i])
			gl.generateMipmap(gl.TEXTURE_2D)
		gl.bindTexture(gl.TEXTURE_2D, null)


