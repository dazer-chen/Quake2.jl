import GL
import GLFW
importall BSP
importall ImmutableArrays
importall Input
importall Player

const near = 4
const far = 16384
projMatrix = eye(Matrix4x4{Float32})
fov = 60.0

function translationMatrix(pos::GL.Vec3)
	x = pos.e1
	y = pos.e2
	z = pos.e3
	Matrix4x4{Float32}(
	Vector4{Float32}(1, 0, 0, 0),
	Vector4{Float32}(0, 1, 0, 0),
	Vector4{Float32}(0, 0, 1, 0),
	Vector4{Float32}(x, y, z, 1))
end

modelMatrix = translationMatrix(GL.Vec3(0, 0, 0))

function updateProjMatrix(width::Cint, height::Cint)
	GL.Viewport(width, height)

	aspect = width / height
	ymax = near * tan(fov * pi / 360)
	ymin = -ymax
	xmin = ymin * aspect
	xmax = ymax * aspect

	x = (2*near) / (xmax-xmin)
	y = (2*near) / (ymax-ymin)
	a = (xmax+xmin) / (xmax-xmin)
	b = (ymax+ymin) / (ymax-ymin)
	c = -(far+near) / (far-near)
	d = -(2*far*near) / (far-near)

	global projMatrix = Matrix4x4{Float32}(
	Vector4{Float32}(x, 0, 0, 0),
	Vector4{Float32}(0, y, 0, 0),
	Vector4{Float32}(a, 0, c,-1),
	Vector4{Float32}(0, 0, d, 0))

	return
end

GLFW.Init()
GLFW.OpenWindowHint(GLFW.OPENGL_VERSION_MAJOR, 4)
GLFW.OpenWindowHint(GLFW.OPENGL_VERSION_MINOR, 2)
GLFW.OpenWindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
GLFW.OpenWindowHint(GLFW.OPENGL_FORWARD_COMPAT, 1)
GLFW.OpenWindow(0, 0, 0, 0, 0, 0, 0, 0, GLFW.WINDOW)
GLFW.SetWindowTitle("Quake 2.jl")
GLFW.SetWindowSizeCallback(updateProjMatrix)
GLFW.SwapInterval(0)

println("Red bits:     ", GLFW.GetWindowParam(GLFW.RED_BITS))
println("Green bits:   ", GLFW.GetWindowParam(GLFW.GREEN_BITS))
println("Blue bits:    ", GLFW.GetWindowParam(GLFW.BLUE_BITS))
println("Alpha bits:   ", GLFW.GetWindowParam(GLFW.ALPHA_BITS))
println("Depth bits:   ", GLFW.GetWindowParam(GLFW.DEPTH_BITS))
println("Stencil bits: ", GLFW.GetWindowParam(GLFW.STENCIL_BITS))

GL.Enable(GL.CULL_FACE)
GL.Enable(GL.DEPTH_TEST)

println("Vendor:   ", GL.GetString(GL.VENDOR))
println("Renderer: ", GL.GetString(GL.RENDERER))
println("Version:  ", GL.GetString(GL.VERSION))
println("GLSL:     ", GL.GetString(GL.SHADING_LANGUAGE_VERSION))

bspFile = open(ARGS[1])
bsp = read(bspFile, Bsp)
close(bspFile)

maxLights = bsp.max_lights + 1

const vertex_shader_src = string("
#version 420

uniform mat4 ModelMatrix;
uniform mat4 ViewMatrix;
uniform mat4 ProjMatrix;

uniform vec4 TexU;
uniform vec4 TexV;
uniform uint TexW;
uniform uint TexH;

uniform vec3 CameraPosition;

in vec3 VertexPosition;

out vec3 FragPosition;
out vec2 TexCoords;
out vec3 ViewDir;

void main()
{
	FragPosition = VertexPosition;
	ViewDir = normalize(VertexPosition - CameraPosition);
	const vec4 pos = vec4(VertexPosition, 1.0);
	TexCoords = vec2(dot(TexU, pos) / TexW, dot(TexV, pos) / TexH);
	gl_Position = ProjMatrix * ViewMatrix * ModelMatrix * pos;
}
")

const fragment_shader_src = string("
#version 420

struct light_t
{
	vec3 Position;
	vec3 Color;
	float Power;
};

uniform vec3 FaceNormal;

uniform bool DiffuseLighting;
uniform bool SpecularLighting;

uniform vec3 AmbientLight;
uniform int NumLights;
uniform light_t Light[", maxLights, "];

uniform bool DiffuseMapping;
uniform sampler2D DiffuseMap;
uniform sampler2D NormalMap;

uniform vec4 TexU;
uniform vec4 TexV;

in vec3 FragPosition;
in vec2 TexCoords;
in vec3 ViewDir;

out vec4 FragColor;

void main()
{
	const vec3 tang = normalize(TexU.xyz);
	const vec3 bitang = normalize(TexV.xyz);
	const mat3 toTangentSpace = mat3(
		tang.x, bitang.x, FaceNormal.x,
		tang.y, bitang.y, FaceNormal.y,
		tang.z, bitang.z, FaceNormal.z );
	const vec3 normal = texture(NormalMap, TexCoords).xyz;
	vec3 LightColor = AmbientLight;
	vec3 camReflectDir = reflect(toTangentSpace * ViewDir, normal);
	for (int i = 0; i < NumLights; i++) {
		vec3 lightDir = toTangentSpace * normalize(Light[i].Position - FragPosition);
		float dirMod = dot(normal, lightDir); // -1 to 1
		dirMod = max(dirMod, 0);
		float lightDist = distance(Light[i].Position, FragPosition);
		float distMod = (Light[i].Power - lightDist) / Light[i].Power;
		distMod = pow(clamp(distMod, 0.0, 1.0), 2);
		if (DiffuseLighting) {
			LightColor += Light[i].Color * dirMod * distMod;
		}
		if (SpecularLighting) {
			LightColor += Light[i].Color * pow(max(dot(lightDir, camReflectDir), 0.0), 10) * distMod * 0.8;
		}
	}
	LightColor = min(LightColor, vec3(1.0, 1.0, 1.0));
	if (true) {
		FragColor = vec4(texture(DiffuseMap, TexCoords).rgb * LightColor, 1.0);
	} else {
		FragColor = vec4(LightColor, 1.0);
	}
}
")

vertex_shader = GL.CreateShader(GL.VERTEX_SHADER)
GL.ShaderSource(vertex_shader, vertex_shader_src)
GL.CompileShader(vertex_shader)

fragment_shader = GL.CreateShader(GL.FRAGMENT_SHADER)
GL.ShaderSource(fragment_shader, fragment_shader_src)
GL.CompileShader(fragment_shader)

prog = GL.CreateProgram()
GL.AttachShader(prog, vertex_shader)
GL.AttachShader(prog, fragment_shader)
GL.LinkProgram(prog)

uModel = GL.Uniform(prog, "ModelMatrix")
uView = GL.Uniform(prog, "ViewMatrix")
uProj = GL.Uniform(prog, "ProjMatrix")

uCamPos = GL.Uniform(prog, "CameraPosition")

uNormal = GL.Uniform(prog, "FaceNormal")

uTexU = GL.Uniform(prog, "TexU")
uTexV = GL.Uniform(prog, "TexV")
uTexW = GL.Uniform(prog, "TexW")
uTexH = GL.Uniform(prog, "TexH")

aPosition = GL.GetAttribLocation(prog, "VertexPosition")

vao = GL.GenVertexArray()
GL.BindVertexArray(vao)

positionBuf = GL.GenBuffer()
GL.BindBuffer(GL.ARRAY_BUFFER, positionBuf)
GL.BufferData(GL.ARRAY_BUFFER, bsp.vertices, GL.STATIC_DRAW)
GL.EnableVertexAttribArray(aPosition)
GL.VertexAttribPointer(aPosition, 3, GL.FLOAT, false, 0, 0)
GL.BindBuffer(GL.ARRAY_BUFFER, 0)

GL.BindVertexArray(0)

frames = 0
tic()

function rotationMatrix{T<:Real}(eyeDir::AbstractVector{T}, upDir::AbstractVector{T})
	rightDir = cross(eyeDir, upDir)
	rightDir /= norm(rightDir)
	upDir = cross(rightDir, eyeDir)

	Xx = rightDir.e1
	Xy = rightDir.e2
	Xz = rightDir.e3

	Yx = upDir.e1
	Yy = upDir.e2
	Yz = upDir.e3

	Zx = -eyeDir.e1
	Zy = -eyeDir.e2
	Zz = -eyeDir.e3

	Matrix4x4{Float32}(
	Vector4{Float32}(Xx, Yx, Zx,  0),
	Vector4{Float32}(Xy, Yy, Zy,  0),
	Vector4{Float32}(Xz, Yz, Zz,  0),
	Vector4{Float32}( 0,  0,  0,  1))
end

uAmbient = GL.Uniform(prog, "AmbientLight")
uDiffuse = GL.Uniform(prog, "DiffuseLighting")
uSpecular = GL.Uniform(prog, "SpecularLighting")
numLightsUniform = GL.Uniform(prog, "NumLights")
lightUniforms = Array(GL.Uniform, 0)
for i = 0:maxLights-1
	light = string("Light[", i, "].")
	push!(lightUniforms, GL.Uniform(prog, string(light, "Position")))
	push!(lightUniforms, GL.Uniform(prog, string(light, "Color")))
	push!(lightUniforms, GL.Uniform(prog, string(light, "Power")))
end

GL.UseProgram(prog)
write(GL.Uniform(prog, "DiffuseMap"), int32(0))
write(GL.Uniform(prog, "NormalMap"), int32(1))

light1 = Player.State()
Player.movedir!(light1, GL.Vec3(1,0,0), true)
light1_pow = float32(0)

ambient_lighting_on = true
diffuse_lighting_on = true
specular_lighting_on = true
wireframe_only = false

toggle_ambient_light() = global ambient_lighting_on = !ambient_lighting_on
toggle_diffuse_light() = global diffuse_lighting_on = !diffuse_lighting_on
toggle_specular_light() = global specular_lighting_on = !specular_lighting_on
toggle_wireframe() = global wireframe_only = !wireframe_only

function fire(apply::Bool)
	if apply
		light1.position = Player.self.position
		light1.orientation = Player.self.orientation
		light1.speed = 0
		global light1_pow = float32(300)
	else
		light1.speed = 600
	end
end

bind(GLFW.MOUSE_BUTTON_LEFT, fire)
bind(GLFW.MOUSE_BUTTON_RIGHT, in_grab)
bind(GLFW.KEY_ESC, in_release)

# WASD in Dvorak
bind(',', forward)
bind('A', moveleft)
bind('O', back)
bind('E', moveright)
bind(' ', moveup)
bind(GLFW.KEY_LCTRL, movedown)
bind(GLFW.KEY_LSHIFT, speed)

bind(GLFW.KEY_UP, lookup)
bind(GLFW.KEY_DOWN, lookdown)
bind(GLFW.KEY_LEFT, left)
bind(GLFW.KEY_RIGHT, right)

bind('1', toggle_wireframe)
bind('2', toggle_ambient_light)
bind('3', toggle_diffuse_light)
bind('4', toggle_specular_light)

GLFW.SetKeyCallback(Input.event)
GLFW.SetMouseButtonCallback(Input.event)
GLFW.SetMousePosCallback(Input.look_event)
GLFW.SetMouseWheelCallback(Input.wheel_event)

while GLFW.GetWindowParam(GLFW.OPENED)

	Player.move!(Player.self)
	Player.move!(light1)
	eyedir, updir, rightdir = sphere2cartesian(Player.self.orientation)
	rotMat = rotationMatrix(eyedir, updir)

	GL.Clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT)

	write(uModel, modelMatrix)
	transMat = translationMatrix(-Player.self.position)
	viewMat = rotMat * transMat
	write(uView, viewMat)
	write(uProj, projMatrix)

	write(uCamPos, Player.self.position)

	if wireframe_only
		write(uAmbient, GL.Vec3(0.2, 0.2, 0.2))
	elseif ambient_lighting_on
		write(uAmbient, GL.Vec3(0.05, 0.05, 0.05))
	else
		write(uAmbient, GL.Vec3(0, 0, 0))
	end
	write(uDiffuse, diffuse_lighting_on)
	write(uSpecular, specular_lighting_on)

	write(lightUniforms[1], light1.position)
	write(lightUniforms[2], GL.Vec3(1.0, 1.0, 0.0))
	write(lightUniforms[3], light1_pow)

	GL.BindVertexArray(vao)

	for face = search(bsp, Player.self.position).faces
		write(uNormal, face.normal)

		write(uTexU, face.u_axis)
		write(uTexV, face.v_axis)
		write(uTexW, face.texture.width)
		write(uTexH, face.texture.height)

		write(numLightsUniform, int32(length(face.lights)+1))
		i = 4
		for light = face.lights
			write(lightUniforms[i], light.origin); i += 1
			write(lightUniforms[i], light.color); i += 1
			write(lightUniforms[i], light.power); i += 1
		end

		GL.ActiveTexture(GL.TEXTURE0)
		GL.BindTexture(GL.TEXTURE_2D, face.texture.diffuse)
		GL.ActiveTexture(GL.TEXTURE1)
		GL.BindTexture(GL.TEXTURE_2D, face.texture.normal)

		if wireframe_only
			GL.DrawElements(GL.LINE_LOOP, face.indices)
		else
			GL.DrawElements(GL.TRIANGLES, face.indices)
		end

		GL.GetError()
	end

	GL.BindVertexArray(0)

	GLFW.SwapBuffers()
	frames += 1
end

seconds = toc()
println(frames / seconds, " FPS")

GLFW.Terminate()
