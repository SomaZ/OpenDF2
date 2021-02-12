/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/
#include "tr_local.h"

/*
=================
RB_ShadowTessEnd

=================
*/
void RB_ShadowTessEnd( shaderCommands_t *input, const VertexArraysProperties *vertexArrays ) {

	if (glConfig.stencilBits < 4) {
		ri.Printf(PRINT_ALL, "no stencil bits for stencil writing\n");
		return;
	}

	if (!input->numVertexes || !input->numIndexes || input->useInternalVBO)
	{
		return;
	}

	vertexAttribute_t attribs[ATTR_INDEX_MAX] = {};
	GL_VertexArraysToAttribs(attribs, ARRAY_LEN(attribs), vertexArrays);
	GL_VertexAttribPointers(vertexArrays->numVertexArrays, attribs);

	cullType_t cullType = CT_TWO_SIDED;
	UniformDataWriter uniformDataWriter;
	int stateBits = GLS_SRCBLEND_ONE | GLS_DSTBLEND_ZERO | GLS_DEPTHFUNC_LESS;

	uniformDataWriter.Start(&tr.volumeShadowShader);
	uniformDataWriter.SetUniformMatrix4x4(UNIFORM_MODELVIEWPROJECTIONMATRIX, glState.modelviewProjection);
	uniformDataWriter.SetUniformMatrix4x3(UNIFORM_BONE_MATRICES, &glState.boneMatrices[0][0], glState.numBones);

	vec4_t lightDir;
	VectorCopy(backEnd.currentEntity->modelLightDir, lightDir);
	lightDir[3] = 300.0f;
	if (r_shadows->integer == 2)
	{
		lightDir[2] = 0.0f;
		VectorNormalize(lightDir);
		VectorSet(lightDir, lightDir[0] * 0.3f, lightDir[1] * 0.3f, 1.0f);
		lightDir[3] = backEnd.currentEntity->e.lightingOrigin[2] - backEnd.currentEntity->e.shadowPlane + 64.0f;
	}
	uniformDataWriter.SetUniformVec4(UNIFORM_LIGHTORIGIN, lightDir);

	DrawItem item = {};
	item.renderState.stateBits = stateBits;
	item.renderState.cullType = cullType;
	DepthRange range = { 0.0f, 1.0f };
	item.renderState.depthRange = range;
	item.program = &tr.volumeShadowShader;
	item.ibo = input->externalIBO ? input->externalIBO : backEndData->currentFrame->dynamicIbo;

	item.numAttributes = vertexArrays->numVertexArrays;
	item.attributes = ojkAllocArray<vertexAttribute_t>(
		*backEndData->perFrameMemory, vertexArrays->numVertexArrays);
	memcpy(item.attributes, attribs, sizeof(*item.attributes)* vertexArrays->numVertexArrays);

	item.uniformData = uniformDataWriter.Finish(*backEndData->perFrameMemory);

	RB_FillDrawCommand(item.draw, GL_TRIANGLES, 1, input);

	//uint32_t key = RB_CreateSortKey(item, 15, 15);
	//RB_AddDrawItem(backEndData->currentPass, key, item);

	qglColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
	qglDepthMask(GL_FALSE);
	qglEnable(GL_STENCIL_TEST);
	qglStencilFunc(GL_ALWAYS, 0, 0xff);
	qglStencilOpSeparate(GL_FRONT, GL_KEEP, GL_INCR_WRAP, GL_KEEP);
	qglStencilOpSeparate(GL_BACK, GL_KEEP, GL_DECR_WRAP, GL_KEEP);
	RB_AddDrawItem(NULL, 0, item);
	qglDisable(GL_STENCIL_TEST);
	qglColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
}


/*
=================
RB_ShadowFinish

Darken everything that is is a shadow volume.
We have to delay this until everything has been shadowed,
because otherwise shadows from different body parts would
overlap and double darken.
=================
*/
void RB_ShadowFinish(void) {
	if (r_shadows->integer != 2) {
		return;
	}
	if (glConfig.stencilBits < 4) {
		return;
	}
	qglEnable(GL_STENCIL_TEST);
	qglStencilFunc(GL_NOTEQUAL, 0, 0xff);

	GL_Cull(CT_TWO_SIDED);

	GL_BindToTMU(tr.whiteImage, TB_COLORMAP);

	GL_State(GLS_DEPTHMASK_TRUE | GLS_SRCBLEND_DST_COLOR | GLS_DSTBLEND_ZERO);

	qglViewport(0, 0, glConfig.vidWidth, glConfig.vidHeight);
	qglScissor(0, 0, glConfig.vidWidth, glConfig.vidHeight);
	matrix_t projection;
	Matrix16Ortho(0, glConfig.vidWidth, glConfig.vidHeight, 0, 0, 1, projection);

	GL_Cull(CT_TWO_SIDED);
	GLSL_BindProgram(&tr.textureColorShader);
	vec4_t color;
	VectorSet4(color, 0.6f, 0.6f, 0.6f, 1.0f);
	GLSL_SetUniformVec4(&tr.textureColorShader, UNIFORM_COLOR, color);
	GLSL_SetUniformMatrix4x4(&tr.textureColorShader, UNIFORM_MODELVIEWPROJECTIONMATRIX, projection);

	vec4i_t dstBox;
	vec4_t quadVerts[4];
	vec2_t texCoords[4];
	VectorSet4(dstBox, 0, glConfig.vidHeight, glConfig.vidWidth, 0);

	VectorSet4(quadVerts[0], dstBox[0], dstBox[1], 0, 1);
	VectorSet4(quadVerts[1], dstBox[2], dstBox[1], 0, 1);
	VectorSet4(quadVerts[2], dstBox[2], dstBox[3], 0, 1);
	VectorSet4(quadVerts[3], dstBox[0], dstBox[3], 0, 1);

	RB_InstantQuad2(quadVerts, texCoords);

	qglDisable(GL_STENCIL_TEST);
}


/*
=================
RB_ProjectionShadowDeform

=================
*/
void RB_ProjectionShadowDeform( void ) {
	float	*xyz;
	int		i;
	float	h;
	vec3_t	ground;
	vec3_t	light;
	float	groundDist;
	float	d;
	vec3_t	lightDir;

	xyz = ( float * ) tess.xyz;

	ground[0] = backEnd.ori.axis[0][2];
	ground[1] = backEnd.ori.axis[1][2];
	ground[2] = backEnd.ori.axis[2][2];

	groundDist = backEnd.ori.origin[2] - backEnd.currentEntity->e.shadowPlane;

	VectorCopy( backEnd.currentEntity->modelLightDir, lightDir );
	d = DotProduct( lightDir, ground );
	// don't let the shadows get too long or go negative
	if ( d < 0.5 ) {
		VectorMA( lightDir, (0.5 - d), ground, lightDir );
		d = DotProduct( lightDir, ground );
	}
	d = 1.0 / d;

	light[0] = lightDir[0] * d;
	light[1] = lightDir[1] * d;
	light[2] = lightDir[2] * d;

	for ( i = 0; i < tess.numVertexes; i++, xyz += 4 ) {
		h = DotProduct( xyz, ground ) + groundDist;

		xyz[0] -= light[0] * h;
		xyz[1] -= light[1] * h;
		xyz[2] -= light[2] * h;
	}
}
