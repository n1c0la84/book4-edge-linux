// SPDX-License-Identifier: GPL-2.0-only
/*
 * GPU: Vulkan compute on the Adreno X1-85 (Mesa Turnip). The shader is
 * mm.comp, compiled into the binary (glslc -mfmt=c). Buffers are host
 * visible: the GPU shares RAM with the CPU, so "copies" are memcpy into
 * mapped memory, and the kernel time is submit to fence.
 */
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

#include "backend.h"

static const uint32_t spv[] =
#include "mm.spv.inc"
;

static struct {
	VkInstance inst;
	VkPhysicalDevice phys;
	VkDevice dev;
	VkQueue queue;
	VkBuffer buf[3];
	VkDeviceMemory mem[3];
	void *map[3];
	VkDescriptorSetLayout dsl;
	VkPipelineLayout pl;
	VkShaderModule sm;
	VkPipeline pipe;
	VkDescriptorPool dp;
	VkDescriptorSet ds;
	VkCommandPool cp;
	VkCommandBuffer cb;
	VkFence fence;
} g;

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
	fprintf(stderr, "gpu: %s failed: %d\n", #x, r_); return -1; } } while (0)

static int find_memory(uint32_t types, VkMemoryPropertyFlags want)
{
	VkPhysicalDeviceMemoryProperties mp;

	vkGetPhysicalDeviceMemoryProperties(g.phys, &mp);
	for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
		if ((types & (1u << i)) && (mp.memoryTypes[i].propertyFlags & want) == want)
			return i;
	return -1;
}

static int gpu_init(int n)
{
	VkDeviceSize size = (VkDeviceSize)n * n * sizeof(float);
	uint32_t count = 1, qf = UINT32_MAX;

	VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
		.pApplicationName = "book4-bench", .apiVersion = VK_API_VERSION_1_1 };
	VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
	CHECK(vkCreateInstance(&ici, NULL, &g.inst));
	if (vkEnumeratePhysicalDevices(g.inst, &count, &g.phys) < 0 || !count) {
		fprintf(stderr, "gpu: no Vulkan device\n");
		return -1;
	}

	static int said;
	if (!said++) {
		VkPhysicalDeviceProperties pp;
		vkGetPhysicalDeviceProperties(g.phys, &pp);
		fprintf(stderr, "gpu: %s\n", pp.deviceName);
	}

	VkQueueFamilyProperties qfp[8];
	uint32_t nq = 8;
	vkGetPhysicalDeviceQueueFamilyProperties(g.phys, &nq, qfp);
	for (uint32_t i = 0; i < nq && qf == UINT32_MAX; i++)
		if (qfp[i].queueFlags & VK_QUEUE_COMPUTE_BIT)
			qf = i;
	if (qf == UINT32_MAX)
		return -1;

	float prio = 1.0f;
	VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
		.queueFamilyIndex = qf, .queueCount = 1, .pQueuePriorities = &prio };
	VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
		.queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
	CHECK(vkCreateDevice(g.phys, &dci, NULL, &g.dev));
	vkGetDeviceQueue(g.dev, qf, 0, &g.queue);

	for (int i = 0; i < 3; i++) {
		VkBufferCreateInfo bci = { .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = size,
			.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
		VkMemoryRequirements mr;
		int mt;

		CHECK(vkCreateBuffer(g.dev, &bci, NULL, &g.buf[i]));
		vkGetBufferMemoryRequirements(g.dev, g.buf[i], &mr);
		/* cached for the read back of C, plain coherent otherwise */
		mt = find_memory(mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
				 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT);
		if (mt < 0)
			mt = find_memory(mr.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
					 VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
		if (mt < 0)
			return -1;
		VkMemoryAllocateInfo mai = { .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
			.allocationSize = mr.size, .memoryTypeIndex = mt };
		CHECK(vkAllocateMemory(g.dev, &mai, NULL, &g.mem[i]));
		CHECK(vkBindBufferMemory(g.dev, g.buf[i], g.mem[i], 0));
		CHECK(vkMapMemory(g.dev, g.mem[i], 0, size, 0, &g.map[i]));
	}

	VkDescriptorSetLayoutBinding b[3];
	for (int i = 0; i < 3; i++)
		b[i] = (VkDescriptorSetLayoutBinding){ .binding = i, .descriptorCount = 1,
			.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT };
	VkDescriptorSetLayoutCreateInfo dlci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		.bindingCount = 3, .pBindings = b };
	CHECK(vkCreateDescriptorSetLayout(g.dev, &dlci, NULL, &g.dsl));

	VkPushConstantRange pcr = { .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT, .size = sizeof(uint32_t) };
	VkPipelineLayoutCreateInfo plci = { .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
		.setLayoutCount = 1, .pSetLayouts = &g.dsl, .pushConstantRangeCount = 1, .pPushConstantRanges = &pcr };
	CHECK(vkCreatePipelineLayout(g.dev, &plci, NULL, &g.pl));

	VkShaderModuleCreateInfo smci = { .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
		.codeSize = sizeof(spv), .pCode = spv };
	CHECK(vkCreateShaderModule(g.dev, &smci, NULL, &g.sm));
	VkComputePipelineCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
		.stage = { .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
			   .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = g.sm, .pName = "main" },
		.layout = g.pl };
	CHECK(vkCreateComputePipelines(g.dev, VK_NULL_HANDLE, 1, &cpci, NULL, &g.pipe));

	VkDescriptorPoolSize ps = { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 3 };
	VkDescriptorPoolCreateInfo dpci = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
		.maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
	CHECK(vkCreateDescriptorPool(g.dev, &dpci, NULL, &g.dp));
	VkDescriptorSetAllocateInfo dsai = { .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
		.descriptorPool = g.dp, .descriptorSetCount = 1, .pSetLayouts = &g.dsl };
	CHECK(vkAllocateDescriptorSets(g.dev, &dsai, &g.ds));
	VkDescriptorBufferInfo dbi[3];
	VkWriteDescriptorSet w[3];
	for (int i = 0; i < 3; i++) {
		dbi[i] = (VkDescriptorBufferInfo){ .buffer = g.buf[i], .range = VK_WHOLE_SIZE };
		w[i] = (VkWriteDescriptorSet){ .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = g.ds,
			.dstBinding = i, .descriptorCount = 1, .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
			.pBufferInfo = &dbi[i] };
	}
	vkUpdateDescriptorSets(g.dev, 3, w, 0, NULL);

	VkCommandPoolCreateInfo cpi = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = qf };
	CHECK(vkCreateCommandPool(g.dev, &cpi, NULL, &g.cp));
	VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
		.commandPool = g.cp, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
	CHECK(vkAllocateCommandBuffers(g.dev, &cbai, &g.cb));

	/* recorded once, submitted every run */
	uint32_t un = n;
	VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
	CHECK(vkBeginCommandBuffer(g.cb, &bi));
	vkCmdBindPipeline(g.cb, VK_PIPELINE_BIND_POINT_COMPUTE, g.pipe);
	vkCmdBindDescriptorSets(g.cb, VK_PIPELINE_BIND_POINT_COMPUTE, g.pl, 0, 1, &g.ds, 0, NULL);
	vkCmdPushConstants(g.cb, g.pl, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(un), &un);
	vkCmdDispatch(g.cb, n / 16, n / 16, 1);
	VkMemoryBarrier mb = { .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
		.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT, .dstAccessMask = VK_ACCESS_HOST_READ_BIT };
	vkCmdPipelineBarrier(g.cb, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0,
			     1, &mb, 0, NULL, 0, NULL);
	CHECK(vkEndCommandBuffer(g.cb));

	VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
	CHECK(vkCreateFence(g.dev, &fci, NULL, &g.fence));
	return 0;
}

static int gpu_run(const float *A, const float *B, float *C, int n, double *kernel_s)
{
	size_t size = (size_t)n * n * sizeof(float);
	VkSubmitInfo si = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &g.cb };

	memcpy(g.map[0], A, size);
	memcpy(g.map[1], B, size);
	double t0 = now();
	CHECK(vkQueueSubmit(g.queue, 1, &si, g.fence));
	CHECK(vkWaitForFences(g.dev, 1, &g.fence, VK_TRUE, UINT64_MAX));
	*kernel_s = now() - t0;
	CHECK(vkResetFences(g.dev, 1, &g.fence));
	memcpy(C, g.map[2], size);
	return 0;
}

static void gpu_fini(void)
{
	if (!g.dev)
		goto out;
	vkDeviceWaitIdle(g.dev);
	vkDestroyFence(g.dev, g.fence, NULL);
	vkDestroyCommandPool(g.dev, g.cp, NULL);
	vkDestroyDescriptorPool(g.dev, g.dp, NULL);
	vkDestroyPipeline(g.dev, g.pipe, NULL);
	vkDestroyShaderModule(g.dev, g.sm, NULL);
	vkDestroyPipelineLayout(g.dev, g.pl, NULL);
	vkDestroyDescriptorSetLayout(g.dev, g.dsl, NULL);
	for (int i = 0; i < 3; i++) {
		if (g.map[i])
			vkUnmapMemory(g.dev, g.mem[i]);
		vkDestroyBuffer(g.dev, g.buf[i], NULL);
		vkFreeMemory(g.dev, g.mem[i], NULL);
	}
	vkDestroyDevice(g.dev, NULL);
out:
	if (g.inst)
		vkDestroyInstance(g.inst, NULL);
	memset(&g, 0, sizeof(g));
}

const struct backend backend_gpu = { "gpu", gpu_init, gpu_run, gpu_fini };
