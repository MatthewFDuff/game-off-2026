#include "voxel_mesher.h"

using namespace godot;

namespace voxel {

namespace {

constexpr int32_t NO_FACE = -1;
constexpr int32_t MERGEABLE_BIT = 1 << 16;

inline int vertex_ao(bool side1, bool side2, bool corner) {
	if (side1 && side2) {
		return 0;
	}
	return 3 - (int(side1) + int(side2) + int(corner));
}

} // namespace

void mesh_padded_chunk(const uint8_t *padded, float voxel_size, const uint8_t *translucent, MeshBuffers &out, MeshBuffers &translucent_out) {
	out.clear();
	translucent_out.clear();

	int32_t mask[CHUNK_SIZE * CHUNK_SIZE];

	// Index strides of the padded volume for x, y, z (see padded_index).
	static const int STRIDE[3] = { 1, PADDED_SIZE * PADDED_SIZE, PADDED_SIZE };
	const int origin = padded_index(0, 0, 0);

	for (int d = 0; d < 3; d++) {
		const int u = (d + 1) % 3;
		const int v = (d + 2) % 3;
		const int sd = STRIDE[d], su = STRIDE[u], sv = STRIDE[v];

		for (int s = -1; s <= 1; s += 2) {
			Vector3 normal;
			normal[d] = float(s);
			const int to_neighbor = s * sd;

			for (int k = 0; k < CHUNK_SIZE; k++) {
				// Build the face mask for this slice.
				for (int j = 0; j < CHUNK_SIZE; j++) {
					const int row = origin + k * sd + j * sv;
					int32_t *mask_row = mask + j * CHUNK_SIZE;
					for (int i = 0; i < CHUNK_SIZE; i++) {
						const int idx = row + i * su;
						const uint8_t m = padded[idx];
						const int n = idx + to_neighbor;
						const uint8_t facing = padded[n];
						// Hidden unless the neighbour is air, or glass of another material than this voxel.
						if (m == 0 || (facing != 0 && (!translucent[facing] || facing == m))) {
							mask_row[i] = NO_FACE;
							continue;
						}
						// The eight voxels around the face's neighbor cell decide its corner AO.
						const bool u_lo = padded[n - su] != 0, u_hi = padded[n + su] != 0;
						const bool v_lo = padded[n - sv] != 0, v_hi = padded[n + sv] != 0;
						const int ao0 = vertex_ao(u_lo, v_lo, padded[n - su - sv] != 0);
						const int ao1 = vertex_ao(u_hi, v_lo, padded[n + su - sv] != 0);
						const int ao2 = vertex_ao(u_hi, v_hi, padded[n + su + sv] != 0);
						const int ao3 = vertex_ao(u_lo, v_hi, padded[n - su + sv] != 0);
						int32_t key = int32_t(m) | (ao0 << 8) | (ao1 << 10) | (ao2 << 12) | (ao3 << 14);
						if (ao0 == ao1 && ao1 == ao2 && ao2 == ao3) {
							key |= MERGEABLE_BIT;
						}
						mask_row[i] = key;
					}
				}

				// Greedily merge the mask into quads.
				for (int j = 0; j < CHUNK_SIZE; j++) {
					for (int i = 0; i < CHUNK_SIZE;) {
						const int32_t key = mask[i + j * CHUNK_SIZE];
						if (key == NO_FACE) {
							i++;
							continue;
						}

						int w = 1;
						int h = 1;
						if (key & MERGEABLE_BIT) {
							while (i + w < CHUNK_SIZE && mask[i + w + j * CHUNK_SIZE] == key) {
								w++;
							}
							bool grow = true;
							while (j + h < CHUNK_SIZE && grow) {
								for (int x = 0; x < w; x++) {
									if (mask[i + x + (j + h) * CHUNK_SIZE] != key) {
										grow = false;
										break;
									}
								}
								if (grow) {
									h++;
								}
							}
						}

						const int ao0 = (key >> 8) & 3;
						const int ao1 = (key >> 10) & 3;
						const int ao2 = (key >> 12) & 3;
						const int ao3 = (key >> 14) & 3;
						const float material = float(key & 0xFF) / 255.0f;
						const float plane = float(k + (s > 0 ? 1 : 0));
						MeshBuffers &dst = translucent[key & 0xFF] ? translucent_out : out;

						const int32_t base = int32_t(dst.vertices.size());
						const int qu[4] = { i, i + w, i + w, i };
						const int qv[4] = { j, j, j + h, j + h };
						const int aos[4] = { ao0, ao1, ao2, ao3 };
						for (int c = 0; c < 4; c++) {
							Vector3 pos;
							pos[d] = plane * voxel_size;
							pos[u] = float(qu[c]) * voxel_size;
							pos[v] = float(qv[c]) * voxel_size;
							dst.vertices.push_back(pos);
							dst.normals.push_back(normal);
							dst.colors.push_back(Color(float(aos[c]) / 3.0f, material, 0.0f, 1.0f));
						}

						// Godot treats clockwise triangles as front-facing. (u, v, d) is right-handed, so
						// corners 0..3 run counter-clockwise when seen from +d. Pick the diagonal that keeps
						// AO gradients from smearing across the quad.
						const bool flip = (ao0 + ao2) < (ao1 + ao3);
						static const int POS_A[6] = { 0, 2, 1, 0, 3, 2 };
						static const int POS_B[6] = { 0, 3, 1, 1, 3, 2 };
						static const int NEG_A[6] = { 0, 1, 2, 0, 2, 3 };
						static const int NEG_B[6] = { 0, 1, 3, 1, 2, 3 };
						const int *tri = s > 0 ? (flip ? POS_B : POS_A) : (flip ? NEG_B : NEG_A);
						for (int t = 0; t < 6; t++) {
							dst.indices.push_back(base + tri[t]);
						}

						for (int y = 0; y < h; y++) {
							for (int x = 0; x < w; x++) {
								mask[i + x + (j + y) * CHUNK_SIZE] = NO_FACE;
							}
						}
						i += w;
					}
				}
			}
		}
	}
}

} // namespace voxel
