using System;
using System.Linq;
using OpenTK;
using OpenTK.Graphics.OpenGL;
namespace opentk
{
	public static partial class RenderPassFactory
	{
		/// <summary>
		/// given color and depth textures, render them.
		/// </summary>
		private static RenderPass CreateSolidSphere
		(
			 FramebufferBindingSet targets,
			 BufferObject<Vector4> sprite_pos_buffer,
			 BufferObject<Vector4> sprite_color_buffer,
			 BufferObject<Vector4> sprite_dimensions_buffer,
			 IValueProvider<Vector2> viewport,
			 IValueProvider<int> particles_count,
			 IValueProvider<float> particle_scale_factor,
			 IValueProvider<Matrix4> modelview_transform,
			 IValueProvider<Matrix4> modelview_inv_transform,
			 IValueProvider<Matrix4> modelviewprojection_transform,
			 IValueProvider<Matrix4> modelviewprojection_inv_transform,
			 IValueProvider<Matrix4> projection_transform,
			 IValueProvider<Matrix4> projection_inv_transform
		)
		{
			var uniform_state = new UniformState ();
			uniform_state.Set ("viewport_size", viewport);

			uniform_state.Set ("modelview_transform", modelview_transform);
			uniform_state.Set ("modelviewprojection_transform", modelviewprojection_transform);
			uniform_state.Set ("projection_transform", projection_transform);
			uniform_state.Set ("projection_inv_transform", projection_inv_transform);
			uniform_state.Set ("modelview_inv_transform", modelview_inv_transform);
			uniform_state.Set ("modelviewprojection_inv_transform", modelviewprojection_inv_transform);
			uniform_state.Set ("particle_scale_factor", particle_scale_factor);

			var array_state =
				new ArrayObject (
					new VertexAttribute { AttributeName = "sprite_pos", Buffer = sprite_pos_buffer, Size = 3, Stride = 16, Type = VertexAttribPointerType.Float },
					new VertexAttribute { AttributeName = "sprite_color", Buffer = sprite_color_buffer, Size = 3, Stride = 16, Type = VertexAttribPointerType.Float },
					new VertexAttribute { AttributeName = "sprite_dimensions", Buffer = sprite_dimensions_buffer, Size = 3, Stride = 16, Type = VertexAttribPointerType.Float }
				);

			//
			var resultPass = new SeparateProgramPass<object>
			(
				 "solid_sphere", "RenderPassFactory",
				 //before state
				 null,
				 //before render
				 null,
				 //render code
				 (window) =>
				 {
					GL.Clear(ClearBufferMask.ColorBufferBit | ClearBufferMask.DepthBufferBit);
				  GL.Enable (EnableCap.DepthTest);
					GL.DepthMask(true);
					GL.DepthFunc (DepthFunction.Less);
					GL.Disable (EnableCap.Blend);

					//setup viewport
					GL.Viewport(0, 0, (int)viewport.Value.X, (int)viewport.Value.Y);
					GL.DrawArrays (BeginMode.Points, 0, particles_count.Value);
				 },

				 //pass state
				 array_state,
				 uniform_state,
				 targets
			);

			return resultPass;
		}

		/// <summary>
		/// given color and depth textures, render them.
		/// </summary>
		public static RenderPass CreateSolidSphere
		(
			 TextureBase normal_depth_target,
			 TextureBase uv_colorindex_target,
			 TextureBase depth_texture,
			 BufferObject<Vector4> sprite_pos_buffer,
			 BufferObject<Vector4> sprite_color_buffer,
			 BufferObject<Vector4> sprite_dimensions_buffer,
			 IValueProvider<int> particles_count,
			 IValueProvider<float> particle_scale_factor,
			 IValueProvider<Matrix4> modelview_transform,
			 IValueProvider<Matrix4> modelview_inv_transform,
			 IValueProvider<Matrix4> modelviewprojection_transform,
			 IValueProvider<Matrix4> modelviewprojection_inv_transform,
			 IValueProvider<Matrix4> projection_transform,
			 IValueProvider<Matrix4> projection_inv_transform
		)
		{
			var viewport = ValueProvider.Create (() => new Vector2 (depth_texture.Width, depth_texture.Height));

			return CreateSolidSphere
			(
				 new FramebufferBindingSet(
				  new DrawFramebufferBinding { Attachment = FramebufferAttachment.DepthAttachment, Texture = depth_texture },
				  new DrawFramebufferBinding { VariableName = "Fragdata.uv_colorindex_none", Texture = uv_colorindex_target },
				  new DrawFramebufferBinding { VariableName = "Fragdata.normal_depth", Texture = normal_depth_target }
				 ),
				 sprite_pos_buffer, sprite_color_buffer, sprite_dimensions_buffer,
				 viewport,
				 particles_count, particle_scale_factor,
				 modelview_transform, modelview_inv_transform,
				 modelviewprojection_transform, modelviewprojection_inv_transform,
				 projection_transform, projection_inv_transform
			);
		}

		/// <summary>
		/// given color and depth textures, render them.
		/// </summary>
		public static RenderPass CreateSolidSphere
		(
			 TextureBase depth_texture,
			 BufferObject<Vector4> sprite_pos_buffer,
			 BufferObject<Vector4> sprite_color_buffer,
			 BufferObject<Vector4> sprite_dimensions_buffer,
			 IValueProvider<int> particles_count,
			 IValueProvider<float> particle_scale_factor,
			 IValueProvider<Matrix4> modelview_transform,
			 IValueProvider<Matrix4> modelview_inv_transform,
			 IValueProvider<Matrix4> modelviewprojection_transform,
			 IValueProvider<Matrix4> modelviewprojection_inv_transform,
			 IValueProvider<Matrix4> projection_transform,
			 IValueProvider<Matrix4> projection_inv_transform
		)
		{
			var viewport = ValueProvider.Create (() => new Vector2 (depth_texture.Width, depth_texture.Height));
			return CreateSolidSphere
			(
				 new FramebufferBindingSet(
				  new DrawFramebufferBinding { Attachment = FramebufferAttachment.DepthAttachment, Texture = depth_texture }
				 ),
				 sprite_pos_buffer, sprite_color_buffer, sprite_dimensions_buffer,
				 viewport,
				 particles_count, particle_scale_factor,
				 modelview_transform, modelview_inv_transform,
				 modelviewprojection_transform, modelviewprojection_inv_transform,
				 projection_transform, projection_inv_transform
			);
		}
	}
}

